const std = @import("std");
const lexing = @import("lexing");
const type_expressions = @import("type_expressions");

const ParseError = @import("parse_error.zig").ParseError;

pub const TypeExpressionParser = struct {
    lexer: *lexing.Lexer,
    allocator: std.mem.Allocator,

    pub fn init(
        lexer: *lexing.Lexer,
        allocator: std.mem.Allocator,
    ) @This() {
        return .{
            .lexer = lexer,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *@This()) ParseError!*type_expressions.TypeExpression {
        const primary = try self.parsePrimary();
        return self.parseArraySuffixes(primary);
    }

    fn parsePrimary(self: *@This()) ParseError!*type_expressions.TypeExpression {
        const token = self.lexer.next();
        switch (token.kind) {
            .Identifier => return self.allocateTypeExpression(.{ .Named = .{ .name_token = token } }),
            else => return ParseError.ExpectedTypeAnnotation,
        }
    }

    fn parseArraySuffixes(
        self: *@This(),
        base_type_expression: *type_expressions.TypeExpression,
    ) ParseError!*type_expressions.TypeExpression {
        var type_expression = base_type_expression;

        while (self.lexer.peek().kind == .LeftBracket) {
            const left_bracket_token = self.lexer.next();
            const right_bracket_token = self.lexer.next();
            if (right_bracket_token.kind != .RightBracket) {
                return ParseError.ExpectedRightBracket;
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
