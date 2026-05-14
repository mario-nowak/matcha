const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const type_expressions = @import("type_expressions");

const ParseError = @import("parse_error.zig").ParseError;

pub const TypeExpressionParser = struct {
    lexer: *lexing.Lexer,
    allocator: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,

    pub fn init(
        lexer: *lexing.Lexer,
        allocator: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
    ) @This() {
        return .{
            .lexer = lexer,
            .allocator = allocator,
            .diagnostic_store = diagnostic_store,
        };
    }

    pub fn parse(self: *@This()) ParseError!*type_expressions.TypeExpression {
        const primary = try self.parsePrimary();
        return self.parseArraySuffixes(primary);
    }

    fn parsePrimary(self: *@This()) ParseError!*type_expressions.TypeExpression {
        const token = try self.lexer.next();
        switch (token.kind) {
            .Identifier => return self.allocateTypeExpression(.{ .Named = .{ .name_token = token } }),
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected type annotation");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseArraySuffixes(
        self: *@This(),
        base_type_expression: *type_expressions.TypeExpression,
    ) ParseError!*type_expressions.TypeExpression {
        var type_expression = base_type_expression;

        while ((try self.lexer.peek()).kind == .LeftBracket) {
            const left_bracket_token = try self.lexer.next();
            const right_bracket_token = try self.lexer.next();
            if (right_bracket_token.kind != .RightBracket) {
                try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after array type suffix");
                return error.DiagnosticsEmitted;
            }

            type_expression = self.allocateTypeExpression(.{
                .Array = .{
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
    ) *type_expressions.TypeExpression {
        const allocated_type_expression = self.allocator.create(type_expressions.TypeExpression) catch unreachable;
        allocated_type_expression.* = type_expression;

        return allocated_type_expression;
    }
};
