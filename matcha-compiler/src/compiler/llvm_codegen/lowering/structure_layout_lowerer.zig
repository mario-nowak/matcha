const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");

pub const StructureLayoutLowerer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.StructureLayoutKindByTypeId {
        var structure_layout_kind_by_type_id = lowering_types.StructureLayoutKindByTypeId.init(self.arena);

        var types_iterator = analyzed_program.type_store.iterator();
        while (types_iterator.next()) |entry| {
            const structure_type = switch (entry.matcha_type) {
                .Structure => |structure_type| structure_type,
                else => continue,
            };
            const structure_type_id = entry.type_id;
            const structure_runtime_representation = analyzed_program
                .runtime_representation_result
                .runtime_representation_by_type_id
                .get(structure_type_id) orelse unreachable;

            switch (structure_runtime_representation) {
                .None => unreachable,
                .Present => {
                    var field_index_kind_by_definition_index = std.ArrayList(lowering_types.StructureLayoutFieldIndexKind){};
                    var runtime_field_index: u32 = 0;

                    var has_field_with_runtime_representation = false;
                    for (structure_type.fields) |field| {
                        const field_runtime_representation = analyzed_program
                            .runtime_representation_result
                            .runtime_representation_by_type_id
                            .get(field.type_id) orelse unreachable;
                        const field_index_kind: lowering_types.StructureLayoutFieldIndexKind = switch (field_runtime_representation) {
                            .Present => block: {
                                has_field_with_runtime_representation = true;
                                const index = runtime_field_index;
                                runtime_field_index += 1;
                                break :block .{ .Index = index };
                            },
                            .None => .Absent,
                        };

                        field_index_kind_by_definition_index.append(
                            self.arena,
                            field_index_kind,
                        ) catch unreachable;
                    }

                    const structure_layout: lowering_types.StructureLayoutKind = if (has_field_with_runtime_representation) .{
                        .Present = .{
                            .llvm_type_name = self.generateLlvmTypeName(analyzed_program, structure_type),
                            .field_index_kind_by_definition_index = field_index_kind_by_definition_index.toOwnedSlice(self.arena) catch unreachable,
                        },
                        // Structures without any runtime fields don't have a layout.
                    } else .Absent;

                    structure_layout_kind_by_type_id.put(
                        structure_type_id,
                        structure_layout,
                    ) catch unreachable;
                },
            }
        }

        return structure_layout_kind_by_type_id;
    }

    fn generateLlvmTypeName(
        self: *@This(),
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        structure_type: typing.StructureType,
    ) []const u8 {
        const structure_symbol = analyzed_program.resolved_program.symbol_table.getSymbol(structure_type.symbol_id);
        return std.fmt.allocPrint(
            self.arena,
            "matcha.structure.{s}",
            .{structure_symbol.name},
        ) catch unreachable;
    }
};
