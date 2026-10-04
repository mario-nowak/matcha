const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const places = @import("places.zig");

const Value = function_symbol_generator_module.Value;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitImplicitMemberExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const member_access_decision = lowered_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
    switch (member_access_decision) {
        // A unit case used as a value, like `Result.None` or `.None`, constructs the case without a payload
        .UnionConstruction => |union_construction| return emitUnionConstruction(
            emitter,
            union_construction.union_type_id,
            union_construction.case_index,
            null,
            lowered_program,
            environment,
        ),
        .ArrayLength,
        .ArrayMethod,
        .IntegerMethod,
        .StringLength,
        .StringMethod,
        .StructureField,
        .InstanceMethod,
        .TypeFunction,
        => unreachable,
    }
}

pub fn emitMemberExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    member_expression: *const ast.MemberExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const member_access_decision = lowered_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
    switch (member_access_decision) {
        .ArrayLength => {
            const base_value = emitter.emitNode(member_expression.base, lowered_program, environment);

            const length_pointer_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitFieldPointer(
                length_pointer_value,
                lowering.llvm_type.array_llvm_type_name,
                base_value.expectValue(),
                lowering.llvm_type.array_length_field_index,
            );

            const length_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitLoad(length_value, length_pointer_value, "i64");

            return .{ .value = length_value };
        },
        .StringLength => {
            const base_value = emitter.emitNode(member_expression.base, lowered_program, environment);
            const string_parts = emitter.emitStringParts(base_value.expectValue());

            return .{ .value = string_parts.length_value };
        },
        .StructureField => |structure_field| {
            const member_pointer_emission_result = places.emitStructureFieldPointer(
                emitter,
                member_expression,
                structure_field.field_index,
                lowered_program,
                environment,
            );
            const member_pointer_value = switch (member_pointer_emission_result) {
                .value => |value| value,
                .zero_sized => return .zero_sized,
                .statement => unreachable,
            };

            const member_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitLoad(
                member_value,
                member_pointer_value,
                lowered_program.getLlvmIrType(lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?),
            );

            return .{ .value = member_value };
        },
        // A unit case used as a value, like `Result.None` or `.None`, constructs the case without a payload
        .UnionConstruction => |union_construction| return emitUnionConstruction(
            emitter,
            union_construction.union_type_id,
            union_construction.case_index,
            null,
            lowered_program,
            environment,
        ),
        .InstanceMethod => unreachable,
        .TypeFunction => unreachable,
        .ArrayMethod => unreachable,
        .StringMethod => unreachable,
        .IntegerMethod => unreachable,
    }
}

pub fn emitUnionConstruction(
    emitter: *NodeEmitter,
    union_type_id: typing.TypeId,
    case_index: u32,
    optional_payload: ?*const ast.Node,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    // Emit the payload before the allocation, so that an early exit in the payload leaves no wasted allocation behind.
    const optional_payload_value: ?Value = if (optional_payload) |payload|
        switch (emitter.emitNode(payload, lowered_program, environment)) {
            .value => |value| value,
            .zero_sized => null,
            .statement => unreachable,
        }
    else
        null;

    // Allocate the structure of the constructed case
    const union_layout = lowered_program.union_layout_by_type_id.get(union_type_id).?;
    const union_case_layout = union_layout.cases[case_index];
    const union_case_llvm_type = std.fmt.allocPrint(emitter.arena, "%{s}", .{union_case_layout.llvm_type_name}) catch unreachable;
    const union_header_value = emitter.runtime_call_emitter.emitAllocateCall(
        emitter.function_ir_builder,
        emitter.function_symbol_generator,
        union_case_llvm_type,
        1,
    );

    // Store the case index in union
    const case_index_pointer_value = emitter.function_symbol_generator.generateValueName();
    emitter.function_ir_builder.emitFieldPointer(
        case_index_pointer_value,
        union_case_layout.llvm_type_name,
        union_header_value,
        lowering.lowering_types.union_case_index_field_index,
    );
    emitter.function_ir_builder.emitStore(
        std.fmt.allocPrint(emitter.arena, "{d}", .{case_index}) catch unreachable,
        case_index_pointer_value,
        lowering.lowering_types.union_case_index_llvm_type,
    );

    // Store the payload in union
    if (optional_payload_value) |payload_value| {
        const payload_pointer_value = emitter.function_symbol_generator.generateValueName();
        emitter.function_ir_builder.emitFieldPointer(
            payload_pointer_value,
            union_case_layout.llvm_type_name,
            union_header_value,
            lowering.lowering_types.union_payload_field_index,
        );

        const payload_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(optional_payload.?.id).?;
        const payload_llvm_ir_type = lowered_program.getLlvmIrType(payload_type_id);
        emitter.function_ir_builder.emitStore(payload_value, payload_pointer_value, payload_llvm_ir_type);
    }

    return .{ .value = union_header_value };
}

pub fn emitStructureLiteral(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    fields: []const ast.StructureFieldInitializer,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const node_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(node.id) orelse unreachable;
    const structure_type = switch (lowered_program.analyzed_program.type_store.getType(node_type_id)) {
        .Structure => |structure_type| structure_type,
        else => unreachable,
    };
    const structure_layout_kind = lowered_program
        .structure_layout_kind_by_type_id.get(node_type_id) orelse unreachable;

    // Emit the field values before the allocation, so that an early exit in a field value leaves no wasted
    // allocation behind.
    const field_value_emission_results = emitter.arena.alloc(EmissionResult, fields.len) catch unreachable;
    for (fields, field_value_emission_results) |field, *field_value_emission_result| {
        field_value_emission_result.* = emitter.emitNode(field.value, lowered_program, environment);
    }

    const structure_header_value = switch (structure_layout_kind) {
        .Present => |structure_layout| emitter.runtime_call_emitter.emitAllocateCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            std.fmt.allocPrint(emitter.arena, "%{s}", .{structure_layout.llvm_type_name}) catch unreachable,
            1,
        ),
        // Structures without a layout only allocate a single byte for identity comparison
        .Absent => emitter.runtime_call_emitter.emitAllocateAtomicCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            1,
        ),
    };

    for (fields, field_value_emission_results) |field, field_value_emission_result| {
        const field_index = structure_type.getFieldIndex(field.name.kind.Identifier) orelse unreachable;
        const structure_field = structure_type.fields[@intCast(field_index)];
        const structure_layout = switch (structure_layout_kind) {
            .Absent => continue,
            .Present => |structure_layout| structure_layout,
        };
        const layout_field_index = switch (structure_layout.field_index_kind_by_definition_index[field_index]) {
            .Absent => continue,
            .Index => |layout_field_index| layout_field_index,
        };

        const field_pointer_value = emitter.function_symbol_generator.generateValueName();
        emitter.function_ir_builder.emitFieldPointer(
            field_pointer_value,
            structure_layout.llvm_type_name,
            structure_header_value,
            layout_field_index,
        );

        const field_llvm_ir_type = lowered_program.getLlvmIrType(structure_field.type_id);
        emitter.function_ir_builder.emitStore(
            field_value_emission_result.expectValue(),
            field_pointer_value,
            field_llvm_ir_type,
        );
    }

    return .{ .value = structure_header_value };
}

pub fn emitArrayLiteral(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    array_literal: *const ast.ArrayLiteral,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    const array_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(node.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(array_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    const length = array_literal.elements.len;
    const element_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(element_type_id) orelse unreachable;

    // Emit the elements before the allocations, so that an early exit in an element leaves no wasted allocation
    // behind.
    const element_emission_results = emitter.arena.alloc(EmissionResult, length) catch unreachable;
    for (array_literal.elements, element_emission_results) |*element, *element_emission_result| {
        element_emission_result.* = emitter.emitNode(element, lowered_program, environment);
    }

    const header_value = emitter.runtime_call_emitter.emitAllocateCall(
        builder,
        emitter.function_symbol_generator,
        lowering.llvm_type.array_llvm_type,
        1,
    );
    // In case the element type does not have a runtime representation, we can just set the data pointer to null.
    const data_value = if (element_runtime_representation.hasRuntimeRepresentation())
        emitter.runtime_call_emitter.emitAllocateCall(builder, emitter.function_symbol_generator, element_llvm_type, length)
    else
        "null";

    for (element_emission_results, 0..) |element_value, index| {
        if (element_runtime_representation.hasRuntimeRepresentation()) {
            const element_pointer_value = emitter.function_symbol_generator.generateValueName();
            const index_value = std.fmt.allocPrint(emitter.arena, "{d}", .{index}) catch unreachable;
            builder.emitElementPointer(element_pointer_value, element_llvm_type, data_value, index_value);

            builder.emitStore(element_value.expectValue(), element_pointer_value, element_llvm_type);
        }
    }

    const length_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        length_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        header_value,
        lowering.llvm_type.array_length_field_index,
    );

    const length_number_string = std.fmt.allocPrint(emitter.arena, "{d}", .{length}) catch unreachable;
    builder.emitStore(length_number_string, length_pointer_value, "i64");

    const capacity_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        capacity_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        header_value,
        lowering.llvm_type.array_capacity_field_index,
    );
    builder.emitStore(length_number_string, capacity_pointer_value, "i64");

    const data_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        data_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        header_value,
        lowering.llvm_type.array_data_field_index,
    );
    builder.emitStore(data_value, data_pointer_value, "ptr");

    return .{ .value = header_value };
}

pub fn emitIndexExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    index_expression: *const ast.IndexExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    _ = node;
    const pointer_value = places.emitIndexExpressionPointer(emitter, index_expression, lowered_program, environment);

    const base_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(index_expression.base.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(element_type_id) orelse unreachable;
    if (!element_runtime_representation.hasRuntimeRepresentation()) {
        return .zero_sized;
    }

    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    const result_value = emitter.function_symbol_generator.generateValueName();
    emitter.function_ir_builder.emitLoad(result_value, pointer_value.expectValue(), element_llvm_type);

    return .{ .value = result_value };
}
