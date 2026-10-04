const std = @import("std");
const ast = @import("ast");
const CompileError = @import("diagnostics").CompileError;

const control_flow_types = @import("control_flow_types.zig");
const structural_validator = @import("structural_validator.zig");
const exit_behavior_analyzer = @import("exit_behavior_analyzer.zig");

pub const ExitBehavior = control_flow_types.ExitBehavior;
pub const ExitBehaviorByNodeId = control_flow_types.ExitBehaviorByNodeId;

pub const ControlFlowValidator = struct {
    structural_validator: structural_validator.StructuralValidator,
    exit_behavior_analyzer: exit_behavior_analyzer.ExitBehaviorAnalyzer,

    pub fn init(
        structural: structural_validator.StructuralValidator,
        exit_behavior: exit_behavior_analyzer.ExitBehaviorAnalyzer,
    ) @This() {
        return .{
            .structural_validator = structural,
            .exit_behavior_analyzer = exit_behavior,
        };
    }

    pub fn validateProgram(
        self: *@This(),
        program: *const ast.Program,
    ) CompileError!ExitBehaviorByNodeId {
        try self.structural_validator.validateProgram(program);
        return self.exit_behavior_analyzer.analyzeProgram(program);
    }
};
