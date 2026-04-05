const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const name_resolution = @import("name_resolution/module.zig");
const type_checking = @import("type_checking/module.zig");
const control_flow_validation = @import("control_flow/module.zig");

const SemanticError = error{
    BlockMustProduceValue,
    BlockCannotProduceValue,
};

pub const SemanticAnalyzer = struct {
    name_resolver: name_resolution.NameResolver,
    type_checker: type_checking.TypeChecker,
    control_flow_validator: control_flow_validation.ControlFlowValidator,

    pub fn init(
        name_resolver: name_resolution.NameResolver,
        type_checker: type_checking.TypeChecker,
        control_flow_validator: control_flow_validation.ControlFlowValidator,
    ) @This() {
        return .{
            .name_resolver = name_resolver,
            .type_checker = type_checker,
            .control_flow_validator = control_flow_validator,
        };
    }

    pub fn validateProgram(self: *@This(), program: *const ast.Program) !typing.TypedProgram {
        try self.control_flow_validator.validateProgram(program);
        const resolved_program = try self.name_resolver.resolve(program);
        const typed_program = try self.type_checker.check(resolved_program);

        return typed_program;
    }
};
