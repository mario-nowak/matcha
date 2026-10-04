const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const ast = @import("ast");

pub const PatternParser = struct {
    lexer: *lexing.Lexer,
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    next_node_id: *ast.NodeId,

    pub fn init(
        lexer: *lexing.Lexer,
        arena: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
        next_node_id: *ast.NodeId,
    ) @This() {
        return .{
            .lexer = lexer,
            .arena = arena,
            .diagnostic_store = diagnostic_store,
            .next_node_id = next_node_id,
        };
    }

    pub fn parse(self: *@This()) CompileError!ast.Pattern {
        const token = try self.lexer.next();
        switch (token.kind) {
            .minus => return self.parseIntegerLiteral(token),
            .int_literal => return self.createPattern(.{ .integer_literal = .{
                .minus_token = null,
                .literal_token = token,
            } }),
            .boolean_literal => return self.createPattern(.{ .boolean_literal = token }),
            .string_literal => return self.createPattern(.{ .string_literal = token }),
            .dot => return self.parseCase(null, token),
            .identifier => {
                if ((try self.lexer.peek()).kind != .dot) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(
                        self.arena,
                        token,
                        "a pattern must be a literal or a case, use a subjectless match to compare against '{s}'",
                        .{token.kind.identifier},
                    );
                    return error.DiagnosticsEmitted;
                }

                return self.parseCase(token, try self.lexer.next());
            },
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected pattern");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseIntegerLiteral(self: *@This(), minus_token: lexing.Token) CompileError!ast.Pattern {
        const literal_token = try self.lexer.next();
        if (literal_token.kind != .int_literal) {
            try self.diagnostic_store.emitErrorFromToken(literal_token, "expected integer literal after '-' in pattern");
            return error.DiagnosticsEmitted;
        }

        return self.createPattern(.{ .integer_literal = .{
            .minus_token = minus_token,
            .literal_token = literal_token,
        } });
    }

    fn parseCase(self: *@This(), qualifier_token: ?lexing.Token, dot_token: lexing.Token) CompileError!ast.Pattern {
        const case_name_token = try self.lexer.next();
        if (case_name_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(case_name_token, "expected case name after '.' in pattern");
            return error.DiagnosticsEmitted;
        }

        return self.createPattern(.{ .case = .{
            .qualifier_token = qualifier_token,
            .dot_token = dot_token,
            .case_name_token = case_name_token,
            .binding = try self.parsePayloadBinding(),
        } });
    }

    fn parsePayloadBinding(self: *@This()) CompileError!?ast.PayloadBinding {
        if ((try self.lexer.peek()).kind != .left_parenthesis) {
            return null;
        }

        const left_parenthesis = try self.lexer.next();
        const name_token = try self.lexer.next();
        if (name_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(name_token, "expected binding name in payload pattern");
            return error.DiagnosticsEmitted;
        }

        const right_parenthesis = try self.lexer.next();
        if (right_parenthesis.kind != .right_parenthesis) {
            try self.diagnostic_store.emitErrorFromToken(right_parenthesis, "expected ')' after payload binding");
            return error.DiagnosticsEmitted;
        }

        return .{
            .id = self.generateNodeId(),
            .left_parenthesis = left_parenthesis,
            .name_token = name_token,
            .right_parenthesis = right_parenthesis,
        };
    }

    fn createPattern(self: *@This(), kind: ast.PatternKind) ast.Pattern {
        return .{ .id = self.generateNodeId(), .kind = kind };
    }

    fn generateNodeId(self: *@This()) ast.NodeId {
        const id = self.next_node_id.*;
        self.next_node_id.* += 1;
        return id;
    }
};
