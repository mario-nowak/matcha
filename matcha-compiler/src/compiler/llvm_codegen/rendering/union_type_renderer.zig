const std = @import("std");
const lowering = @import("lowering");
const ast = @import("ast");

pub const UnionTypeRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
        };
    }

    pub fn renderUnionTypeDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) []const u8 {
        var union_definitions_buffer = std.ArrayList(u8){};
        defer union_definitions_buffer.deinit(self.allocator);
        const resolved_program = lowered_program.analyzed_program.resolved_program;

        var union_index: usize = 0;

        for (resolved_program.program.statements) |*statement| {
            const item_definition = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.definition) {
                    .Union => item_definition,
                    else => continue,
                },
                else => continue,
            };
            const union_name = item_definition.identifier_token.kind.Identifier;
            const union_definition = item_definition.definition.Union;
            const union_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(statement.id).?;

            for (union_definition.cases, 0..) |union_case, case_index| {
                if (case_index > 0 or (case_index == 0 and union_index > 0)) {
                    union_definitions_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
                }
                union_definitions_buffer.writer(self.allocator).print(
                    "{s}",
                    .{std.fmt.allocPrint(self.allocator, "matcha_union_{d}__{s}__case_{d}__{s}", .{
                        union_symbol_id,
                        union_name,
                        case_index,
                        union_case.name.kind.Identifier,
                    }) catch unreachable},
                ) catch unreachable;
            }
            union_index += 1;
        }

        return union_definitions_buffer.toOwnedSlice(self.allocator) catch unreachable;
    }
};
