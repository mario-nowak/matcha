const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const BinaryOperationLowerer = struct {
    allocator: std.mem.Allocator,
    decision_by_node_id: lowering_types.BinaryOperationDecisionByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .decision_by_node_id = lowering_types.BinaryOperationDecisionByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.decision_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.BinaryOperationDecisionByNodeId {
        _ = analyzed_program;
        self.decision_by_node_id.clearRetainingCapacity();
        return self.decision_by_node_id;
    }
};
