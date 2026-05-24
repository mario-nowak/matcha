const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const NodeValueKindLowerer = struct {
    allocator: std.mem.Allocator,
    value_kind_by_node_id: lowering_types.NodeValueKindByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .value_kind_by_node_id = lowering_types.NodeValueKindByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.value_kind_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.NodeValueKindByNodeId {
        self.value_kind_by_node_id.clearRetainingCapacity();

        var type_by_node_iterator = analyzed_program.type_by_node_id.iterator();
        while (type_by_node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const type_id = entry.value_ptr.*;
            const value_kind: lowering_types.NodeValueKind = if (type_id == analyzed_program.type_store.unit_type_id)
                .NoValue
            else
                .Value;
            self.value_kind_by_node_id.put(node_id, value_kind) catch unreachable;
        }

        return self.value_kind_by_node_id;
    }
};
