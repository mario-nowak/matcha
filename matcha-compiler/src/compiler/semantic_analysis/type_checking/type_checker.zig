const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");

const type_checking_types = @import("type_checking_types.zig");
const type_seeder = @import("type_seeder.zig");
const node_type_analyzer = @import("node_type_analyzer.zig");

pub const TypeError = type_checking_types.TypeError;
pub const TypeCheckResult = type_checking_types.TypeCheckResult;

pub const TypeChecker = struct {
    type_seeder: type_seeder.TypeSeeder,
    node_type_analyzer: node_type_analyzer.NodeTypeAnalyzer,

    pub fn init(
        seeder: type_seeder.TypeSeeder,
        analyzer: node_type_analyzer.NodeTypeAnalyzer,
    ) @This() {
        return .{
            .type_seeder = seeder,
            .node_type_analyzer = analyzer,
        };
    }

    pub fn checkProgram(
        self: *@This(),
        resolved_program: symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!TypeCheckResult {
        self.node_type_analyzer.resetState();
        try self.type_seeder.seedProgram(&self.node_type_analyzer, &resolved_program);
        try self.node_type_analyzer.analyzeProgram(&resolved_program, exit_behavior_by_node_id);

        return self.node_type_analyzer.typeCheckResult();
    }
};
