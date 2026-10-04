const std = @import("std");
const lowering = @import("lowering");
const ast = @import("ast");

const lowering_types = lowering.lowering_types;
const llvm_type_lowering = lowering.llvm_type;

pub const UnionTypeRenderer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn renderUnionTypeDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) ![]const u8 {
        var union_definitions_buffer = std.ArrayList(u8){};
        const analyzed_program = lowered_program.analyzed_program;
        const resolved_program = analyzed_program.resolved_program;

        var union_index: usize = 0;

        for (resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .item_definition => |item_definition| switch (item_definition.definition) {
                    .@"union" => {},
                    else => continue,
                },
                else => continue,
            }
            const union_symbol_id = resolved_program.symbol_id_by_node_id.get(statement.id).?;
            const union_type_id = analyzed_program.type_id_by_symbol_id.get(union_symbol_id).?;
            const union_type = analyzed_program.type_store.getType(union_type_id).@"union";
            const union_layout = lowered_program.union_layout_by_type_id.get(union_type_id).?;

            for (0..union_layout.cases.len) |case_index| {
                if (case_index > 0 or union_index > 0) {
                    try union_definitions_buffer.writer(self.arena).print("\n", .{});
                }

                try union_definitions_buffer.writer(self.arena).print(
                    "%{s} = type {{ {s}",
                    .{ union_layout.cases[case_index].llvm_type_name, lowering_types.union_case_index_llvm_type },
                );

                const payload_type_id = union_type.cases[case_index].type_id;
                const type_runtime_representation = analyzed_program.runtime_representation_result.runtime_representation_by_type_id.get(payload_type_id).?;
                if (type_runtime_representation == .present) {
                    const llvm_type = lowered_program.getLlvmIrType(payload_type_id);
                    try union_definitions_buffer.writer(self.arena).print(", {s} }}", .{llvm_type});
                } else {
                    try union_definitions_buffer.writer(self.arena).print(" }}", .{});
                }
            }

            union_index += 1;
        }

        return union_definitions_buffer.toOwnedSlice(self.arena);
    }
};
