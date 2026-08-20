const std = @import("std");
const ast = @import("ast");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const places = @import("places.zig");

const Register = function_symbol_generator_module.Register;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitMemberAccess(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    member_access: *const ast.MemberAccess,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const member_access_decision = lowered_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
    switch (member_access_decision) {
        .ArrayLength => {
            const base_register = emitter.emitNode(member_access.base, lowered_program, environment);

            const length_pointer_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                emitter.allocator,
                "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
                .{ length_pointer_register, base_register.expectRegister() },
            ) catch unreachable);

            const length_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

            return .{ .register = length_register };
        },
        .StringLength => {
            const base_register = emitter.emitNode(member_access.base, lowered_program, environment);
            const string_parts = emitter.emitStringParts(base_register.expectRegister());

            return .{ .register = string_parts.length_register };
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
                member_pointer_register,
                lowered_program.getLlvmIrType(lowered_program.analyzed_program.type_by_node_id.get(node.id).?),
            );

            return .{ .register = member_register };
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
) EmissionResult {
    const node_type_id = lowered_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const structure_symbol = lowered_program.getStructureSymbolForTypeId(node_type_id);
    const structure_llvm_type_name = emitter.symbol_generator.generateStructureName(structure_symbol);
    const structure_type_id = switch (lowered_program.analyzed_program.type_store.getType(node_type_id)) {
        .Structure => |id| id,
        else => unreachable,
    };
    const structure_type_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(structure_type_id) orelse unreachable;

    const structure_type = lowered_program.analyzed_program.type_store.structure_types.items[structure_type_id];
    const structure_construction_layout = lowered_program.analyzed_program.structure_construction_layout_by_node_id.get(
        node.id,
    ) orelse unreachable;

    var structure_header_register: ?Register = null;
    if (structure_type_runtime_representation.hasRuntimeRepresentation()) {
        structure_header_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitInstruction(
            std.fmt.allocPrint(
                emitter.allocator,
                "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%{s}, ptr null, i32 1) to i64))",
                .{ structure_header_register, structure_llvm_type_name },
            ) catch unreachable,
        );
    }
    for (fields, structure_construction_layout.field_indices) |field, field_index| {
        // todo: This must stay even for structures without runtime representation
        const field_value_emission_result = emitter.emitNode(field.value, lowered_program, environment);
        const structure_field = structure_type.fields[@intCast(field_index)];
        const field_value_runtime_representation = lowered_program
            .analyzed_program
            .runtime_representation_result
            .runtime_representation_by_type_id
            .get(structure_field.type_id) orelse unreachable;
        if (!structure_type_runtime_representation.hasRuntimeRepresentation() or !field_value_runtime_representation.hasRuntimeRepresentation()) {
            // If either the structure or the field value does not have a runtime representation, we can skip storing the field value.
            continue;
        }

        const field_pointer_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ field_pointer_register, structure_llvm_type_name, structure_header_register, field_index },
        ) catch unreachable);

        const field_llvm_ir_type = lowered_program.getLlvmIrType(structure_field.type_id);
        emitter.function_ir_builder.emitStore(
            field_value_emission_result.expectRegister(),
            field_pointer_register,
            field_llvm_ir_type,
        );
    }

    if (structure_type_runtime_representation.hasRuntimeRepresentation()) {
        return .{ .register = structure_header_register.? };
    } else {
        return .zero_sized;
    }
}

pub fn emitArrayLiteral(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    array_literal: *const ast.ArrayLiteral,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    const array_type_id = lowered_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(array_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    const length = array_literal.elements.len;
    const runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(array_type_id) orelse unreachable;
    const element_runtime_representation = switch (runtime_representation) {
        .Array => |array_runtime_representation| lowered_program
            .analyzed_program
            .runtime_representation_result
            .runtime_representation_by_type_id
            .get(array_runtime_representation.element_type_id) orelse unreachable,
        else => unreachable,
    };

    // Array header register
    const header_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))",
        .{header_register},
    ) catch unreachable);

    var data_register = emitter.function_symbol_generator.generateRegister();
    if (element_runtime_representation.hasRuntimeRepresentation()) {
        builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64))",
            .{ data_register, element_llvm_type, length },
        ) catch unreachable);
    } else {
        // In case the element type does not have a runtime representation, we can just set the data pointer to null.
        data_register = "null";
    }

    for (array_literal.elements, 0..) |*element, index| {
        const element_register = emitter.emitNode(element, lowered_program, environment);

        if (element_runtime_representation.hasRuntimeRepresentation()) {
            const element_pointer_register = emitter.function_symbol_generator.generateRegister();
            builder.emitInstruction(std.fmt.allocPrint(
                emitter.allocator,
                "{s} = getelementptr inbounds {s}, ptr {s}, i64 {d}",
                .{ element_pointer_register, element_llvm_type, data_register, index },
            ) catch unreachable);

            builder.emitStore(element_register.expectRegister(), element_pointer_register, element_llvm_type);
        }
    }

    const length_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, header_register },
    ) catch unreachable);

    const length_number_string = std.fmt.allocPrint(emitter.allocator, "{d}", .{length}) catch unreachable;
    builder.emitStore(length_number_string, length_pointer_register, "i64");

    const capacity_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 1",
        .{ capacity_pointer_register, header_register },
    ) catch unreachable);
    builder.emitStore(length_number_string, capacity_pointer_register, "i64");

    const data_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, header_register },
    ) catch unreachable);
    builder.emitStore(data_register, data_pointer_register, "ptr");

    return .{ .register = header_register };
}

pub fn emitIndexAccess(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    index_access: *const ast.IndexAccess,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    _ = node;
    const pointer_register = places.emitIndexAccessPointer(emitter, index_access, lowered_program, environment);

    const base_type_id = lowered_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
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
    const result_register = emitter.function_symbol_generator.generateRegister();
    emitter.function_ir_builder.emitLoad(result_register, pointer_register.expectRegister(), element_llvm_type);

    return .{ .register = result_register };
}
