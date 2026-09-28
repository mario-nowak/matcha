const std = @import("std");
const lowering = @import("lowering");
const ast = @import("ast");

const lowering_types = lowering.lowering_types;
const llvm_type_lowering = lowering.llvm_type;

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
        const analyzed_program = lowered_program.analyzed_program;
        const resolved_program = analyzed_program.resolved_program;

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
            const union_symbol_id = resolved_program.symbol_id_by_node_id.get(statement.id).?;
            const union_symbol = resolved_program.symbol_table.getSymbol(union_symbol_id);
            const union_symbol_information = union_symbol.kind.Union;

            for (union_symbol_information.cases, 0..) |union_case, case_index| {
                if (case_index > 0 or (case_index == 0 and union_index > 0)) {
                    union_definitions_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
                }
                const payload_type_id = llvm_type_lowering.getTypeIdFromResolvedTypeReference(analyzed_program, union_case.type_reference);
                union_definitions_buffer.writer(self.allocator).print(
                    "{s}",
                    .{std.fmt.allocPrint(self.allocator, "%matcha_union_{d}__{s}__case_{d}__{s} = type {{ i8", .{
                        union_symbol_id,
                        union_name,
                        case_index,
                        union_case.name,
                    }) catch unreachable},
                ) catch unreachable;
                const type_runtime_representation = analyzed_program.runtime_representation_result.runtime_representation_by_type_id.get(payload_type_id).?;
                if (type_runtime_representation == .Present) {
                    const llvm_type = lowered_program.getLlvmIrType(payload_type_id);
                    union_definitions_buffer.writer(self.allocator).print(", {s} }}", .{llvm_type}) catch unreachable;
                } else {
                    union_definitions_buffer.writer(self.allocator).print(" }}", .{}) catch unreachable;
                }
            }
            union_index += 1;
        }

        return union_definitions_buffer.toOwnedSlice(self.allocator) catch unreachable;
    }
};
