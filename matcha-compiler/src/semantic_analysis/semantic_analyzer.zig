const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const name_resolution = @import("name_resolution/module.zig");
const type_checking = @import("type_checking/module.zig");

const SemanticError = error{
    BlockMustProduceValue,
    BlockCannotProduceValue,
};

pub const SemanticAnalyzer = struct {
    name_resolver: name_resolution.NameResolver,
    type_checker: type_checking.TypeChecker,

    pub fn init(
        name_resolver: name_resolution.NameResolver,
        type_checker: type_checking.TypeChecker,
    ) @This() {
        return .{
            .name_resolver = name_resolver,
            .type_checker = type_checker,
        };
    }

    pub fn validateProgram(self: *@This(), program: *const ast.Program) !typing.TypedProgram {
        const resolved_program = try self.name_resolver.resolve(program);
        const typed_program = try self.type_checker.check(resolved_program);

        return typed_program;
    }
};
