const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const MemberAccessLowerer = struct {
    allocator: std.mem.Allocator,
    decision_by_node_id: lowering_types.MemberAccessDecisionByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .decision_by_node_id = lowering_types.MemberAccessDecisionByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.decision_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.MemberAccessDecisionByNodeId {
        self.decision_by_node_id.clearRetainingCapacity();

        var member_access_iterator = analyzed_program.member_access_by_node_id.iterator();
        while (member_access_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const member_access = entry.value_ptr.*;
            const decision: lowering_types.MemberAccessDecision = switch (member_access) {
                .StructureInstanceFieldAccess => |structure_field| .{
                    .StructureField = .{ .field_index = structure_field.field_index },
                },
                .UnionTypeFunctionAccess => unreachable,
                .UnionTypeBaseCaseAccess => |base_case_access| .{
                    .UnionConstruction = .{
                        // A base case access constructs the case, so the node has the type of the union
                        .union_type_id = analyzed_program.type_id_by_node_id.get(node_id).?,
                        .case_index = base_case_access.case_index,
                    },
                },
                .InstanceMethodAccess => .InstanceMethod,
                .TypeFunctionAccess => .TypeFunction,
                .ArrayInstanceMethodAccess => .ArrayMethod,
                .ArrayInstanceFieldAccess => .ArrayLength,
                .StringInstanceMethodAccess => .StringMethod,
                .StringInstanceFieldAccess => .StringLength,
                .IntegerInstanceMethodAccess => .IntegerMethod,
            };
            self.decision_by_node_id.put(node_id, decision) catch unreachable;
        }

        return self.decision_by_node_id;
    }
};
