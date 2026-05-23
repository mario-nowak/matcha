const std = @import("std");
const ast = @import("ast");
const lowering = @import("lowering");
const function_emission = @import("function_emission");
const support = @import("node_rendering_support.zig");

const Label = function_emission.Label;
const Environment = support.Environment;
const EmissionResult = support.EmissionResult;

pub fn emitMemberAccess(
    self: anytype,
    node: *const ast.Node,
    member_access: *const ast.MemberAccess,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const member_access_decision = typed_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
    switch (member_access_decision) {
        .ArrayLength => {
            const base_result = self.emitNode(
                member_access.base,
                entry_label,
                typed_program,
                environment,
            );
            if (base_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }

            const length_pointer_register = self.function_symbol_generator.generateRegister();
            self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                self.allocator,
                "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
                .{ length_pointer_register, base_result.register orelse unreachable },
            ) catch unreachable);

            const length_register = self.function_symbol_generator.generateRegister();
            self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

            return .{
                .exit_label = base_result.exit_label,
                .register = length_register,
            };
        },
        .StringLength => {
            const base_result = self.emitNode(
                member_access.base,
                entry_label,
                typed_program,
                environment,
            );
            if (base_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }

            const string_parts = self.emitStringParts(base_result.register orelse unreachable);
            return .{
                .exit_label = base_result.exit_label,
                .register = string_parts.length_register,
            };
        },
        .StructureField => |structure_field| {
            const member_pointer_result = self.emitStructureFieldPointer(
                member_access,
                structure_field.field_index,
                entry_label,
                typed_program,
                environment,
            );
            if (member_pointer_result.exit_label == null) {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }

            const member_register = self.function_symbol_generator.generateRegister();
            self.function_ir_builder.emitLoad(
                member_register,
                member_pointer_result.register.?,
                typed_program.llvmIrType(typed_program.analyzed_program.type_by_node_id.get(node.id).?),
            );

            return .{
                .exit_label = member_pointer_result.exit_label,
                .register = member_register,
            };
        },
        .StructureMethod => unreachable,
        .StructureTypeFunction => unreachable,
        .ArrayMethod => unreachable,
        .StringMethod => unreachable,
        .IntegerMethod => unreachable,
    }
}

pub fn emitPlace(
    self: anytype,
    target: *const ast.Node,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const place_decision = typed_program.place_decision_by_node_id.get(target.id) orelse unreachable;
    return switch (place_decision) {
        .IdentifierBinding => |identifier_binding| .{
            .exit_label = entry_label,
            .register = environment.storage_by_symbol_id.get(identifier_binding.symbol_id).?,
        },
        .StructureField => |structure_field| {
            const member_access = switch (target.kind) {
                .MemberAccess => |resolved_member_access| resolved_member_access,
                else => unreachable,
            };
            return self.emitStructureFieldPointer(
                &member_access,
                structure_field.field_index,
                entry_label,
                typed_program,
                environment,
            );
        },
        .ArrayElement => {
            const index_access = switch (target.kind) {
                .IndexAccess => |resolved_index_access| resolved_index_access,
                else => unreachable,
            };
            return self.emitIndexAccessPointer(
                &index_access,
                entry_label,
                typed_program,
                environment,
            );
        },
    };
}

pub fn emitStructureFieldPointer(
    self: anytype,
    member_access: *const ast.MemberAccess,
    field_index: u32,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const base_result = self.emitNode(
        member_access.base,
        entry_label,
        typed_program,
        environment,
    );
    if (base_result.exit_label == null) {
        return .{
            .exit_label = null,
            .register = null,
        };
    }

    const base_type_id = typed_program.analyzed_program.type_by_node_id.get(member_access.base.id) orelse unreachable;
    switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
        .Structure => {},
        else => unreachable,
    }
    const structure_symbol = typed_program.structureSymbolForTypeId(base_type_id);
    const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);

    const field_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
        .{ field_pointer_register, structure_llvm_type_name, base_result.register orelse unreachable, field_index },
    ) catch unreachable);

    return .{
        .exit_label = base_result.exit_label,
        .register = field_pointer_register,
    };
}

pub fn emitStructureConstruction(
    self: anytype,
    node: *const ast.Node,
    fields: []const ast.StructureConstructionField,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const node_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const structure_symbol = typed_program.structureSymbolForTypeId(node_type_id);
    const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);
    const structure_type_id = switch (typed_program.analyzed_program.type_store.getType(node_type_id)) {
        .Structure => |id| id,
        else => unreachable,
    };
    const structure_type = typed_program.analyzed_program.type_store.structure_types.items[structure_type_id];
    const structure_construction_layout = typed_program.analyzed_program.structure_construction_layout_by_node_id.get(
        node.id,
    ) orelse unreachable;

    const memory_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(
        std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%{s}, ptr null, i32 1) to i64))",
            .{ memory_register, structure_llvm_type_name },
        ) catch unreachable,
    );

    var current_label: Label = entry_label;
    for (fields, structure_construction_layout.field_indices) |field, field_index| {
        const structure_field = structure_type.fields[@intCast(field_index)];
        const field_value_result = self.emitNode(
            field.value,
            current_label,
            typed_program,
            environment,
        );
        if (field_value_result.exit_label == null) {
            return .{
                .exit_label = null,
                .register = null,
            };
        }
        current_label = field_value_result.exit_label.?;

        const field_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ field_pointer_register, structure_llvm_type_name, memory_register, field_index },
        ) catch unreachable);

        const field_llvm_ir_type = typed_program.llvmIrType(structure_field.type_id);
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ field_llvm_ir_type, field_value_result.register orelse unreachable, field_pointer_register },
        ) catch unreachable);
    }

    return .{
        .exit_label = current_label,
        .register = memory_register,
    };
}

pub fn emitArrayLiteral(
    self: anytype,
    node: *const ast.Node,
    array_literal: *const ast.ArrayLiteral,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const array_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
    const element_type_id = switch (typed_program.analyzed_program.type_store.getType(array_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = typed_program.llvmIrType(element_type_id);
    const length = array_literal.elements.len;

    const header_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))",
        .{header_register},
    ) catch unreachable);

    const data_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64))",
        .{ data_register, element_llvm_type, length },
    ) catch unreachable);

    var current_label: Label = entry_label;
    for (array_literal.elements, 0..) |*element, index| {
        const element_result = self.emitNode(element, current_label, typed_program, environment);
        if (element_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }
        current_label = element_result.exit_label.?;

        const element_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {d}",
            .{ element_pointer_register, element_llvm_type, data_register, index },
        ) catch unreachable);

        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ element_llvm_type, element_result.register orelse unreachable, element_pointer_register },
        ) catch unreachable);
    }

    const length_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, header_register },
    ) catch unreachable);
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "store i64 {d}, ptr {s}",
        .{ length, length_pointer_register },
    ) catch unreachable);

    const capacity_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 1",
        .{ capacity_pointer_register, header_register },
    ) catch unreachable);
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "store i64 {d}, ptr {s}",
        .{ length, capacity_pointer_register },
    ) catch unreachable);

    const data_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, header_register },
    ) catch unreachable);
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "store ptr {s}, ptr {s}",
        .{ data_register, data_pointer_register },
    ) catch unreachable);

    return .{
        .exit_label = current_label,
        .register = header_register,
    };
}

pub fn emitIndexAccess(
    self: anytype,
    node: *const ast.Node,
    index_access: *const ast.IndexAccess,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    _ = node;
    const pointer_result = self.emitIndexAccessPointer(
        index_access,
        entry_label,
        typed_program,
        environment,
    );
    if (pointer_result.exit_label == null) {
        return .{ .exit_label = null, .register = null };
    }

    const base_type_id = typed_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
    const element_type_id = switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = typed_program.llvmIrType(element_type_id);

    const result_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(result_register, pointer_result.register orelse unreachable, element_llvm_type);

    return .{
        .exit_label = pointer_result.exit_label,
        .register = result_register,
    };
}

pub fn emitIndexAccessPointer(
    self: anytype,
    index_access: *const ast.IndexAccess,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const base_result = self.emitNode(index_access.base, entry_label, typed_program, environment);
    if (base_result.exit_label == null) {
        return .{ .exit_label = null, .register = null };
    }

    const index_result = self.emitNode(index_access.index, base_result.exit_label.?, typed_program, environment);
    if (index_result.exit_label == null) {
        return .{ .exit_label = null, .register = null };
    }

    const base_type_id = typed_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
    const element_type_id = switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = typed_program.llvmIrType(element_type_id);

    const length_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, base_result.register orelse unreachable },
    ) catch unreachable);

    const length_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

    const data_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, base_result.register orelse unreachable },
    ) catch unreachable);

    const data_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(data_register, data_pointer_register, "ptr");

    const negative_check_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = icmp slt i64 {s}, 0",
        .{ negative_check_register, index_result.register orelse unreachable },
    ) catch unreachable);

    const overflow_check_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = icmp sge i64 {s}, {s}",
        .{ overflow_check_register, index_result.register orelse unreachable, length_register },
    ) catch unreachable);

    const out_of_bounds_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = or i1 {s}, {s}",
        .{ out_of_bounds_register, negative_check_register, overflow_check_register },
    ) catch unreachable);

    const panic_label = self.function_symbol_generator.generateLabel("index_panic");
    const ok_label = self.function_symbol_generator.generateLabel("index_ok");
    self.function_ir_builder.emitBranchInstruction(out_of_bounds_register, &.{ panic_label, ok_label });

    self.function_ir_builder.emitLabel(panic_label);
    const line = index_access.left_bracket.line;
    const column = index_access.left_bracket.column;
    self.runtime_call_emitter.emitPanicIndexOutOfBoundsCall(
        self.function_ir_builder,
        line,
        column,
        index_result.register orelse unreachable,
        length_register,
    );
    self.function_ir_builder.emitInstruction("unreachable");

    self.function_ir_builder.emitLabel(ok_label);
    const element_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
        .{ element_pointer_register, element_llvm_type, data_register, index_result.register orelse unreachable },
    ) catch unreachable);

    return .{
        .exit_label = ok_label,
        .register = element_pointer_register,
    };
}
