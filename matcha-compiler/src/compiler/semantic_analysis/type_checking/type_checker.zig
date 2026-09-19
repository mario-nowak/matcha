const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");

const type_checking_types = @import("type_checking_types.zig");
const node_type_analyzer = @import("node_type_analyzer.zig");

pub const TypeError = type_checking_types.TypeError;
pub const TypeCheckResult = type_checking_types.TypeCheckResult;

// TODO: remove this wrapper
pub const TypeChecker = struct {
    node_type_analyzer: node_type_analyzer.NodeTypeAnalyzer,

    pub fn init(
        analyzer: node_type_analyzer.NodeTypeAnalyzer,
    ) @This() {
        return .{
            .node_type_analyzer = analyzer,
        };
    }

    pub fn checkProgram(
        self: *@This(),
        resolved_program: symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!TypeCheckResult {
        const type_check_result = try self.node_type_analyzer.analyzeProgram(
            &resolved_program,
            exit_behavior_by_node_id,
        );

        return type_check_result;
    }
};
