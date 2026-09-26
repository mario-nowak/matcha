const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const ast = @import("ast");

const ParseError = @import("parse_error.zig").ParseError;

pub const PatternParser = struct {
    lexer: *lexing.Lexer,
    allocator: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    next_node_id: *ast.NodeId,

    pub fn init(
        lexer: *lexing.Lexer,
        allocator: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
        next_node_id: *ast.NodeId,
    ) @This() {
        return .{
            .lexer = lexer,
            .allocator = allocator,
            .diagnostic_store = diagnostic_store,
            .next_node_id = next_node_id,
        };
    }

    pub fn parse(self: *@This()) ParseError!ast.Pattern {
        const token = try self.lexer.next();
        switch (token.kind) {
            .Minus => return self.parseIntegerLiteral(token),
            .IntLiteral => return self.createPattern(.{ .IntegerLiteral = .{
                .minus_token = null,
                .literal_token = token,
            } }),
            .BooleanLiteral => return self.createPattern(.{ .BooleanLiteral = token }),
            .StringLiteral => return self.createPattern(.{ .StringLiteral = token }),
            .Dot => return self.parseCase(null, token),
            .Identifier => {
                const dot_token = try self.lexer.next();
                if (dot_token.kind != .Dot) {
                    try self.diagnostic_store.emitErrorFromToken(dot_token, "expected '.' after union name in pattern");
                    return error.DiagnosticsEmitted;
                }

                return self.parseCase(token, dot_token);
            },
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected pattern");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseIntegerLiteral(self: *@This(), minus_token: lexing.Token) ParseError!ast.Pattern {
        const literal_token = try self.lexer.next();
        if (literal_token.kind != .IntLiteral) {
            try self.diagnostic_store.emitErrorFromToken(literal_token, "expected integer literal after '-' in pattern");
            return error.DiagnosticsEmitted;
        }

        return self.createPattern(.{ .IntegerLiteral = .{
            .minus_token = minus_token,
            .literal_token = literal_token,
        } });
    }

    fn parseCase(self: *@This(), qualifier_token: ?lexing.Token, dot_token: lexing.Token) ParseError!ast.Pattern {
        const case_name_token = try self.lexer.next();
        if (case_name_token.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(case_name_token, "expected case name after '.' in pattern");
            return error.DiagnosticsEmitted;
        }

        return self.createPattern(.{ .Case = .{
            .qualifier_token = qualifier_token,
            .dot_token = dot_token,
            .case_name_token = case_name_token,
            .binding = try self.parsePayloadBinding(),
        } });
    }

    fn parsePayloadBinding(self: *@This()) ParseError!?ast.PayloadBinding {
        if ((try self.lexer.peek()).kind != .LeftParenthesis) {
            return null;
        }

        const left_parenthesis = try self.lexer.next();
        const name_token = try self.lexer.next();
        if (name_token.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(name_token, "expected binding name in payload pattern");
            return error.DiagnosticsEmitted;
        }

        const right_parenthesis = try self.lexer.next();
        if (right_parenthesis.kind != .RightParenthesis) {
            try self.diagnostic_store.emitErrorFromToken(right_parenthesis, "expected ')' after payload binding");
            return error.DiagnosticsEmitted;
        }

        return .{
            .left_parenthesis = left_parenthesis,
            .name_token = name_token,
            .right_parenthesis = right_parenthesis,
        };
    }

    fn createPattern(self: *@This(), kind: ast.PatternKind) ast.Pattern {
        const id = self.next_node_id.*;
        self.next_node_id.* += 1;
        return .{ .id = id, .kind = kind };
    }
};
