const std = @import("std");
const ast = @import("ast");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const places = @import("places.zig");

const Register = function_symbol_generator_module.Register;
const NodeEmitter = node_emitter_module.NodeEmitter;
const Environment = node_emitter_module.Environment;

pub fn emitMemberAccess(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    member_access: *const ast.MemberAccess,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const member_access_decision = lowered_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
    switch (member_access_decision) {
        .ArrayLength => {
            const base_register = emitter.emitNode(member_access.base, lowered_program, environment);

            const length_pointer_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                emitter.allocator,
                "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
                .{ length_pointer_register, base_register orelse unreachable },
            ) catch unreachable);

            const length_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

            return length_register;
        },
        .StringLength => {
            const base_register = emitter.emitNode(member_access.base, lowered_program, environment);
            const string_parts = emitter.emitStringParts(base_register orelse unreachable);

            return string_parts.length_register;
        },
        .StructureField => |structure_field| {
            const member_pointer_register = places.emitStructureFieldPointer(
                emitter,
                member_access,
                structure_field.field_index,
                lowered_program,
                environment,
            );

            const member_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitLoad(
                member_register,
                member_pointer_register.?,
                lowered_program.getLlvmIrType(lowered_program.analyzed_program.type_by_node_id.get(node.id).?),
            );

            return member_register;
        },
        .StructureMethod => unreachable,
        .StructureTypeFunction => unreachable,
        .ArrayMethod => unreachable,
        .StringMethod => unreachable,
        .IntegerMethod => unreachable,
    }
}

pub fn emitStructureConstruction(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    fields: []const ast.StructureConstructionField,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const node_type_id = lowered_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const structure_symbol = lowered_program.getStructureSymbolForTypeId(node_type_id);
    const structure_llvm_type_name = emitter.symbol_generator.generateStructureName(structure_symbol);
    const structure_type_id = switch (lowered_program.analyzed_program.type_store.getType(node_type_id)) {
        .Structure => |id| id,
        else => unreachable,
    };
    const structure_type = lowered_program.analyzed_program.type_store.structure_types.items[structure_type_id];
    const structure_construction_layout = lowered_program.analyzed_program.structure_construction_layout_by_node_id.get(
        node.id,
    ) orelse unreachable;

    const memory_register = emitter.function_symbol_generator.generateRegister();
    emitter.function_ir_builder.emitInstruction(
        std.fmt.allocPrint(
            emitter.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%{s}, ptr null, i32 1) to i64))",
            .{ memory_register, structure_llvm_type_name },
        ) catch unreachable,
    );

    for (fields, structure_construction_layout.field_indices) |field, field_index| {
        const structure_field = structure_type.fields[@intCast(field_index)];
        const field_value_register = emitter.emitNode(field.value, lowered_program, environment);

        const field_pointer_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ field_pointer_register, structure_llvm_type_name, memory_register, field_index },
        ) catch unreachable);

        const field_llvm_ir_type = lowered_program.getLlvmIrType(structure_field.type_id);
        emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "store {s} {s}, ptr {s}",
            .{ field_llvm_ir_type, field_value_register orelse unreachable, field_pointer_register },
        ) catch unreachable);
    }

    return memory_register;
}

pub fn emitArrayLiteral(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    array_literal: *const ast.ArrayLiteral,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    const builder = emitter.function_ir_builder;
    const array_type_id = lowered_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(array_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    const length = array_literal.elements.len;

    const header_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))",
        .{header_register},
    ) catch unreachable);

    const data_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64))",
        .{ data_register, element_llvm_type, length },
    ) catch unreachable);

    for (array_literal.elements, 0..) |*element, index| {
        const element_register = emitter.emitNode(element, lowered_program, environment);

        const element_pointer_register = emitter.function_symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {d}",
            .{ element_pointer_register, element_llvm_type, data_register, index },
        ) catch unreachable);

        builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "store {s} {s}, ptr {s}",
            .{ element_llvm_type, element_register orelse unreachable, element_pointer_register },
        ) catch unreachable);
    }

    const length_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, header_register },
    ) catch unreachable);
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "store i64 {d}, ptr {s}",
        .{ length, length_pointer_register },
    ) catch unreachable);

    const capacity_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 1",
        .{ capacity_pointer_register, header_register },
    ) catch unreachable);
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "store i64 {d}, ptr {s}",
        .{ length, capacity_pointer_register },
    ) catch unreachable);

    const data_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, header_register },
    ) catch unreachable);
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "store ptr {s}, ptr {s}",
        .{ data_register, data_pointer_register },
    ) catch unreachable);

    return header_register;
}

pub fn emitIndexAccess(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    index_access: *const ast.IndexAccess,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) ?Register {
    _ = node;
    const pointer_register = places.emitIndexAccessPointer(emitter, index_access, lowered_program, environment);

    const base_type_id = lowered_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);

    const result_register = emitter.function_symbol_generator.generateRegister();
    emitter.function_ir_builder.emitLoad(result_register, pointer_register orelse unreachable, element_llvm_type);

    return result_register;
}
