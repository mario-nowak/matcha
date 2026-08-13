const std = @import("std");
const ast = @import("ast");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const values = @import("values.zig");

const Register = function_symbol_generator_module.Register;
const NodeEmitter = node_emitter_module.NodeEmitter;
const Environment = node_emitter_module.Environment;

pub fn emitDeclaration(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    value_declaration: *const ast.Declaration,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const value_register = emitter.emitNode(value_declaration.value, lowered_program, environment);
    const symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
    const value_type_id = lowered_program.analyzed_program.type_by_node_id.get(value_declaration.value.id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(value_type_id);

    const storage = emitter.function_symbol_generator.generateStorage();
    emitter.function_ir_builder.emitAlloca(storage, llvm_ir_type);
    emitter.function_ir_builder.emitStore(value_register.?, storage, llvm_ir_type);

    environment.storage_by_symbol_id.put(symbol_id, storage) catch unreachable;

    return null;
}

pub fn emitAssignment(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    assignment: *const ast.Assignment,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const place_register = emitPlace(emitter, assignment.target, lowered_program, environment);

    const value_type_id = lowered_program.analyzed_program.type_by_node_id.get(assignment.target.id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(value_type_id);
    switch (assignment.operator) {
        .Assign => {
            const value_register = emitter.emitNode(assignment.value, lowered_program, environment);
            emitter.function_ir_builder.emitStore(value_register.?, place_register.?, llvm_ir_type);
        },
        .Compound => {
            const current_value_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitLoad(current_value_register, place_register.?, llvm_ir_type);

            const value_register = emitter.emitNode(assignment.value, lowered_program, environment);
            const result_register = values.emitLoweredBinaryOperation(
                emitter,
                lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
                value_type_id,
                current_value_register,
                value_register.?,
                lowered_program,
            );
            emitter.function_ir_builder.emitStore(result_register, place_register.?, llvm_ir_type);
        },
    }
    return null;
}

pub fn emitPlace(
    emitter: *NodeEmitter,
    target: *const ast.Node,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const place_decision = lowered_program.place_decision_by_node_id.get(target.id) orelse unreachable;
    switch (place_decision) {
        .IdentifierBinding => |identifier_binding| {
            return environment.storage_by_symbol_id.get(identifier_binding.symbol_id).?;
        },
        .StructureField => |structure_field| {
            const member_access = switch (target.kind) {
                .MemberAccess => |resolved_member_access| resolved_member_access,
                else => unreachable,
            };
            return emitStructureFieldPointer(
                emitter,
                &member_access,
                structure_field.field_index,
                lowered_program,
                environment,
            );
        },
        .ArrayElement => {
            const index_access = switch (target.kind) {
                .IndexAccess => |resolved_index_access| resolved_index_access,
                else => unreachable,
            };
            return emitIndexAccessPointer(emitter, &index_access, lowered_program, environment);
        },
    }
}

pub fn emitStructureFieldPointer(
    emitter: *NodeEmitter,
    member_access: *const ast.MemberAccess,
    field_index: u32,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const base_register = emitter.emitNode(member_access.base, lowered_program, environment);

    const base_type_id = lowered_program.analyzed_program.type_by_node_id.get(member_access.base.id) orelse unreachable;
    switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Structure => {},
        else => unreachable,
    }
    const structure_symbol = lowered_program.getStructureSymbolForTypeId(base_type_id);
    const structure_llvm_type_name = emitter.symbol_generator.generateStructureName(structure_symbol);

    const field_pointer_register = emitter.function_symbol_generator.generateRegister();
    emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
        .{ field_pointer_register, structure_llvm_type_name, base_register orelse unreachable, field_index },
    ) catch unreachable);

    return field_pointer_register;
}

pub fn emitIndexAccessPointer(
    emitter: *NodeEmitter,
    index_access: *const ast.IndexAccess,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const builder = emitter.function_ir_builder;
    const base_register = emitter.emitNode(index_access.base, lowered_program, environment);
    const index_register = emitter.emitNode(index_access.index, lowered_program, environment);

    const base_type_id = lowered_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);

    const length_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, base_register orelse unreachable },
    ) catch unreachable);

    const length_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(length_register, length_pointer_register, "i64");

    const data_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, base_register orelse unreachable },
    ) catch unreachable);

    const data_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(data_register, data_pointer_register, "ptr");

    const negative_check_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = icmp slt i64 {s}, 0",
        .{ negative_check_register, index_register orelse unreachable },
    ) catch unreachable);

    const overflow_check_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = icmp sge i64 {s}, {s}",
        .{ overflow_check_register, index_register orelse unreachable, length_register },
    ) catch unreachable);

    const out_of_bounds_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = or i1 {s}, {s}",
        .{ out_of_bounds_register, negative_check_register, overflow_check_register },
    ) catch unreachable);

    const panic_label = emitter.function_symbol_generator.generateLabel("index_panic");
    const ok_label = emitter.function_symbol_generator.generateLabel("index_ok");
    builder.emitBranchInstruction(out_of_bounds_register, &.{ panic_label, ok_label });

    builder.emitLabel(panic_label);
    const line = index_access.left_bracket.line;
    const column = index_access.left_bracket.column;
    emitter.runtime_call_emitter.emitPanicIndexOutOfBoundsCall(
        builder,
        line,
        column,
        index_register orelse unreachable,
        length_register,
    );
    builder.emitTerminatorInstruction("unreachable");

    builder.emitLabel(ok_label);
    const element_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
        .{ element_pointer_register, element_llvm_type, data_register, index_register orelse unreachable },
    ) catch unreachable);

    return element_pointer_register;
}
