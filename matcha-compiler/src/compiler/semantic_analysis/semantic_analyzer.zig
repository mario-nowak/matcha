const std = @import("std");
const ast = @import("ast");
const analyzed_program_module = @import("analyzed_program.zig");
const name_resolution = @import("name_resolution/module.zig");
const type_checking = @import("type_checking/module.zig");
const control_flow_validation = @import("control_flow/module.zig");
const runtime_representation = @import("runtime_representation/module.zig");

pub const SemanticAnalyzer = struct {
    name_resolver: name_resolution.NameResolver,
    type_checker: type_checking.TypeChecker,
    control_flow_validator: control_flow_validation.ControlFlowValidator,
    runtime_representation_analyzer: runtime_representation.RuntimeRepresentationAnalyzer,

    pub fn init(
        name_resolver: name_resolution.NameResolver,
        type_checker: type_checking.TypeChecker,
        control_flow_validator: control_flow_validation.ControlFlowValidator,
        runtime_representation_analyzer: runtime_representation.RuntimeRepresentationAnalyzer,
    ) @This() {
        return .{
            .name_resolver = name_resolver,
            .type_checker = type_checker,
            .control_flow_validator = control_flow_validator,
            .runtime_representation_analyzer = runtime_representation_analyzer,
        };
    }

    pub fn analyzeProgram(self: *@This(), program: *const ast.Program) !analyzed_program_module.AnalyzedProgram {
        const exit_behavior_by_node_id = try self.control_flow_validator.validateProgram(program);
        const resolved_program = try self.name_resolver.resolveProgram(program);
        const type_check_result = try self.type_checker.checkProgram(resolved_program, exit_behavior_by_node_id);
        const runtime_representation_result = try self.runtime_representation_analyzer.analyzeProgram(
            &resolved_program,
            exit_behavior_by_node_id,
            &type_check_result,
        );

        return analyzed_program_module.AnalyzedProgram.init(
            resolved_program,
            exit_behavior_by_node_id,
            type_check_result,
            runtime_representation_result,
        );
    }
};
