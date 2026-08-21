const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const StructureLayoutLowerer = struct {
    allocator: std.mem.Allocator,
    structure_layout_kind_by_type_id: lowering_types.StructureLayoutKindByTypeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .structure_layout_kind_by_type_id = lowering_types.StructureLayoutKindByTypeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.clearLayouts();
        self.structure_layout_kind_by_type_id.deinit();
    }

    fn clearLayouts(self: *@This()) void {
        var layouts = self.structure_layout_kind_by_type_id.valueIterator();
        while (layouts.next()) |layout| {
            switch (layout.*) {
                .Absent => {},
                .Present => |present| self.allocator.free(present.runtime_field_index_by_semantic_index),
            }
        }
        self.structure_layout_kind_by_type_id.clearRetainingCapacity();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.StructureLayoutKindByTypeId {
        self.clearLayouts();

        for (analyzed_program.type_store.structure_types.items) |structure_type| {
            const structure_type_id = analyzed_program.type_by_symbol_id.get(structure_type.symbol_id) orelse unreachable;
            const structure_runtime_representation = analyzed_program
                .runtime_representation_result
                .runtime_representation_by_type_id
                .get(structure_type_id) orelse unreachable;

            switch (structure_runtime_representation) {
                .Array => unreachable,
                .None => {
                    self.structure_layout_kind_by_type_id.put(
                        structure_type_id,
                        lowering_types.StructureLayoutKind.Absent,
                    ) catch unreachable;
                },
                .Present => {
                    var runtime_field_index_by_semantic_index = std.ArrayList(lowering_types.RuntimeFieldIndex){};
                    defer runtime_field_index_by_semantic_index.deinit(self.allocator);
                    var runtime_field_index: u32 = 0;

                    for (structure_type.fields) |field| {
                        const field_runtime_representation = analyzed_program
                            .runtime_representation_result
                            .runtime_representation_by_type_id
                            .get(field.type_id) orelse unreachable;
                        const field_index: lowering_types.RuntimeFieldIndex = switch (field_runtime_representation) {
                            .Present, .Array => block: {
                                const index = runtime_field_index;
                                runtime_field_index += 1;
                                break :block .{ .Index = index };
                            },
                            .None => .Absent,
                        };

                        runtime_field_index_by_semantic_index.append(
                            self.allocator,
                            field_index,
                        ) catch unreachable;
                    }

                    self.structure_layout_kind_by_type_id.put(
                        structure_type_id,
                        .{
                            .Present = .{
                                .runtime_field_index_by_semantic_index = runtime_field_index_by_semantic_index.toOwnedSlice(self.allocator) catch unreachable,
                            },
                        },
                    ) catch unreachable;
                },
            }
        }

        return self.structure_layout_kind_by_type_id;
    }
};
