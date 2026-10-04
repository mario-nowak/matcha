const std = @import("std");
const ast = @import("ast");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const values = @import("values.zig");

const Value = function_symbol_generator_module.Value;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitBindingDeclaration(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    value_declaration: *const ast.BindingDeclaration,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    // Regardless of the runtime representation of the value node, we still must emit it because it may have side
    // effects. For example, a function call that returns unit may still have side effects.
    const initial_value = emitter.emitNode(value_declaration.value, lowered_program, environment);

    const runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_node_id
        .get(value_declaration.value.id) orelse unreachable;

    if (!runtime_representation.hasRuntimeRepresentation()) {
        return .zero_sized;
    }

    const symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
    const value_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(value_declaration.value.id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(value_type_id);

    const binding_name = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id).name;
    const address = emitter.function_symbol_generator.generateBindingAddressName(binding_name);
    emitter.function_ir_builder.emitStackAllocation(address, llvm_ir_type);
    emitter.function_ir_builder.emitStore(initial_value.expectValue(), address, llvm_ir_type);

    environment.address_by_symbol_id.put(symbol_id, address) catch unreachable;

    return .statement;
}

pub fn emitAssignmentStatement(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    assignment_statement: *const ast.AssignmentStatement,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const place_emission_result = emitPlace(emitter, assignment_statement.target, lowered_program, environment);

    const value_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(assignment_statement.target.id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(value_type_id);
    switch (assignment_statement.operator) {
        .Assign => {
            const assigned_value = emitter.emitNode(assignment_statement.value, lowered_program, environment);
            const place_address = switch (place_emission_result) {
                .zero_sized => return .statement,
                .value => |place_address| place_address,
                .statement => unreachable,
            };
            emitter.function_ir_builder.emitStore(assigned_value.expectValue(), place_address, llvm_ir_type);
        },
        .Compound => {
            const assigned_value = emitter.emitNode(assignment_statement.value, lowered_program, environment);
            const place_address = switch (place_emission_result) {
                .zero_sized => return .statement,
                .value => |place_address| place_address,
                .statement => unreachable,
            };

            const current_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitLoad(current_value, place_address, llvm_ir_type);

            const result_value = values.emitLoweredBinaryOperation(
                emitter,
                lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
                value_type_id,
                current_value,
                assigned_value.expectValue(),
                lowered_program,
            );
            emitter.function_ir_builder.emitStore(result_value, place_address, llvm_ir_type);
        },
    }
    return .statement;
}

pub fn emitPlace(
    emitter: *NodeEmitter,
    target: *const ast.Node,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const place_decision = lowered_program.place_decision_by_node_id.get(target.id) orelse unreachable;

    switch (place_decision) {
        .IdentifierBinding => |identifier_binding| {
            const target_runtime_representation = lowered_program
                .analyzed_program
                .runtime_representation_result
                .runtime_representation_by_node_id
                .get(target.id) orelse unreachable;
            if (!target_runtime_representation.hasRuntimeRepresentation()) {
                return .zero_sized;
            }
            return .{ .value = environment.address_by_symbol_id.get(identifier_binding.symbol_id).? };
        },
        .StructureField => |structure_field| {
            const member_expression = switch (target.kind) {
                .MemberExpression => |resolved_member_expression| resolved_member_expression,
                else => unreachable,
            };
            return emitStructureFieldPointer(
                emitter,
                &member_expression,
                structure_field.field_index,
                lowered_program,
                environment,
            );
        },
        .ArrayElement => {
            const index_expression = switch (target.kind) {
                .IndexExpression => |resolved_index_expression| resolved_index_expression,
                else => unreachable,
            };
            return emitIndexExpressionPointer(emitter, &index_expression, lowered_program, environment);
        },
    }
}

pub fn emitStructureFieldPointer(
    emitter: *NodeEmitter,
    member_expression: *const ast.MemberExpression,
    field_index: u32,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    // First check if the base expression of the member access has a runtime representation and exit early if not
    const base_emission_result = emitter.emitNode(member_expression.base, lowered_program, environment);
    const base_value = switch (base_emission_result) {
        .value => |value| value,
        .zero_sized => return .zero_sized,
        .statement => unreachable,
    };

    const base_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(member_expression.base.id) orelse unreachable;
    switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Structure => {},
        else => unreachable,
    }

    const structure_layout = switch (lowered_program.structure_layout_kind_by_type_id.get(base_type_id) orelse unreachable) {
        .Absent => return .zero_sized,
        .Present => |structure_layout| structure_layout,
    };
    const field_layout_index = switch (structure_layout.field_index_kind_by_definition_index[field_index]) {
        .Absent => return .zero_sized,
        .Index => |field_layout_index| field_layout_index,
    };

    const field_pointer_value = emitter.function_symbol_generator.generateValueName();
    emitter.function_ir_builder.emitFieldPointer(
        field_pointer_value,
        structure_layout.llvm_type_name,
        base_value,
        field_layout_index,
    );

    return .{ .value = field_pointer_value };
}

pub fn emitIndexExpressionPointer(
    emitter: *NodeEmitter,
    index_expression: *const ast.IndexExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    const base_value = emitter.emitNode(index_expression.base, lowered_program, environment).expectValue();
    const index_value = emitter.emitNode(index_expression.index, lowered_program, environment).expectValue();

    const base_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(index_expression.base.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };

    // Perform bounds check
    const length_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        length_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        base_value,
        lowering.llvm_type.array_length_field_index,
    );

    const length_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(length_value, length_pointer_value, "i64");

    const data_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        data_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        base_value,
        lowering.llvm_type.array_data_field_index,
    );

    const negative_check_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = icmp slt i64 {s}, 0",
        .{ negative_check_value, index_value },
    ) catch unreachable);

    const overflow_check_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = icmp sge i64 {s}, {s}",
        .{ overflow_check_value, index_value, length_value },
    ) catch unreachable);

    const out_of_bounds_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = or i1 {s}, {s}",
        .{ out_of_bounds_value, negative_check_value, overflow_check_value },
    ) catch unreachable);

    const panic_label = emitter.function_symbol_generator.generateLabel("index_panic");
    const ok_label = emitter.function_symbol_generator.generateLabel("index_ok");
    builder.emitBranchInstruction(out_of_bounds_value, &.{ panic_label, ok_label });

    builder.emitLabel(panic_label);
    const line = index_expression.left_bracket.line;
    const column = index_expression.left_bracket.column;
    emitter.runtime_call_emitter.emitPanicIndexOutOfBoundsCall(
        builder,
        line,
        column,
        index_value,
        length_value,
    );
    builder.emitTerminatorInstruction("unreachable");

    builder.emitLabel(ok_label);
    const element_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(element_type_id) orelse unreachable;
    // Compute the pointer to the element at the given index if bounds check passes
    if (!element_runtime_representation.hasRuntimeRepresentation()) {
        return .zero_sized;
    }
    const data_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(data_value, data_pointer_value, "ptr");
    const element_pointer_value = emitter.function_symbol_generator.generateValueName();
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    builder.emitElementPointer(element_pointer_value, element_llvm_type, data_value, index_value);

    return .{ .value = element_pointer_value };
}
