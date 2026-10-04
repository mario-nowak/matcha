const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const type_expressions = @import("type_expressions");

pub const TypeExpressionParser = struct {
    lexer: *lexing.Lexer,
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,

    pub fn init(
        lexer: *lexing.Lexer,
        arena: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
    ) @This() {
        return .{
            .lexer = lexer,
            .arena = arena,
            .diagnostic_store = diagnostic_store,
        };
    }

    pub fn parse(self: *@This()) CompileError!*type_expressions.TypeExpression {
        const primary = try self.parsePrimary();
        return self.parseArraySuffixes(primary);
    }

    fn parsePrimary(self: *@This()) CompileError!*type_expressions.TypeExpression {
        const token = try self.lexer.next();
        switch (token.kind) {
            .identifier => return self.allocateTypeExpression(.{ .named = .{ .name_token = token } }),
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected type annotation");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseArraySuffixes(
        self: *@This(),
        base_type_expression: *type_expressions.TypeExpression,
    ) CompileError!*type_expressions.TypeExpression {
        var type_expression = base_type_expression;

        while ((try self.lexer.peek()).kind == .left_bracket) {
            const left_bracket_token = try self.lexer.next();
            const right_bracket_token = try self.lexer.next();
            if (right_bracket_token.kind != .right_bracket) {
                try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after array type suffix");
                return error.DiagnosticsEmitted;
            }

            type_expression = try self.allocateTypeExpression(.{
                .array = .{
                    .element_type = type_expression,
                    .left_bracket_token = left_bracket_token,
                    .right_bracket_token = right_bracket_token,
                },
            });
        }

        return type_expression;
    }

    fn allocateTypeExpression(
        self: *@This(),
        type_expression: type_expressions.TypeExpression,
    ) !*type_expressions.TypeExpression {
        const allocated_type_expression = try self.arena.create(type_expressions.TypeExpression);
        allocated_type_expression.* = type_expression;

        return allocated_type_expression;
    }
};
