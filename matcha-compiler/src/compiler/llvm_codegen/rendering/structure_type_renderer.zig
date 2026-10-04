const std = @import("std");
const typing = @import("typing");
const lowering = @import("lowering");
const lowering_types = lowering.lowering_types;

pub const StructureTypeRenderer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn renderStructureTypeDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) ![]const u8 {
        var structure_definitions_buffer = std.ArrayList(u8){};
        const resolved_program = lowered_program.analyzed_program.resolved_program;

        var has_structure_definition = false;
        for (resolved_program.program.statements) |*statement| {
            _ = switch (statement.kind) {
                .item_definition => |item_definition| switch (item_definition.definition) {
                    .structure => |structure| structure,
                    else => continue,
                },
                else => continue,
            };

            const structure_symbol_id = resolved_program.symbol_id_by_node_id.get(statement.id) orelse unreachable;
            const structure_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id) orelse unreachable;
            const structure_layout_kind = lowered_program.structure_layout_kind_by_type_id.get(structure_type_id) orelse unreachable;
            const structure_layout = switch (structure_layout_kind) {
                .absent => continue,
                .present => |structure_layout| structure_layout,
            };

            if (has_structure_definition) {
                try structure_definitions_buffer.writer(self.arena).print("\n", .{});
            }
            try structure_definitions_buffer.writer(self.arena).print(
                "{s}",
                .{
                    try self.renderStructureTypeDefinition(
                        lowered_program.analyzed_program.type_store.getType(structure_type_id).structure,
                        structure_layout,
                        lowered_program,
                    ),
                },
            );
            has_structure_definition = true;
        }

        return std.fmt.allocPrint(self.arena, "{s}", .{structure_definitions_buffer.items});
    }

    fn renderStructureTypeDefinition(
        self: *@This(),
        structure_type: typing.StructureType,
        structure_layout: lowering_types.StructureLayout,
        lowered_program: *const lowering.LoweredProgram,
    ) ![]const u8 {
        const structure_llvm_type_name = structure_layout.llvm_type_name;

        var structure_definition_buffer = std.ArrayList(u8){};

        try structure_definition_buffer.writer(self.arena).print(
            "%{s} = type {{",
            .{structure_llvm_type_name},
        );
        for (structure_type.fields, 0..) |field, field_index_in_structure_definition| {
            const field_index = switch (structure_layout.field_index_kind_by_definition_index[field_index_in_structure_definition]) {
                .absent => continue,
                .index => |field_index| field_index,
            };

            if (field_index == 0) {
                try structure_definition_buffer.writer(self.arena).print(" ", .{});
            } else {
                try structure_definition_buffer.writer(self.arena).print(", ", .{});
            }

            try structure_definition_buffer.writer(self.arena).print(
                "{s}",
                .{lowered_program.getLlvmIrType(field.type_id)},
            );
        }
        if (structure_type.fields.len > 0) {
            try structure_definition_buffer.writer(self.arena).print(" ", .{});
        }
        try structure_definition_buffer.writer(self.arena).print("}}", .{});

        return std.fmt.allocPrint(self.arena, "{s}", .{structure_definition_buffer.items});
    }
};
