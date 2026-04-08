pub const TokenKind = union(enum) {
    // Keywords
    Val,
    Var,
    If,
    Else,
    Not,
    And,
    Or,
    Loop,
    Leave,
    Continue,
    While,
    // Punctuation
    LeftParenthesis,
    RightParenthesis,
    LeftBrace,
    RightBrace,
    Assign,
    EqualEqual,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
    Colon,
    Semicolon,
    Plus,
    Minus,
    Asterisk,
    Slash,
    Comma,
    //
    Identifier: []const u8,
    IntLiteral: i64,
    RealLiteral: f64,
    BooleanLiteral: bool,
    //
    EndOfFile,
    Error: struct {
        message: []const u8,
    },
};

pub const Token = struct {
    line: usize,
    column: usize,
    offsetInSource: usize,
    lenInSource: u32,
    kind: TokenKind,

    pub fn format(
        self: Token,
        writer: anytype,
    ) !void {
        try writer.print("Token(line={}, col={}, type=", .{ self.line, self.column });

        switch (self.kind) {
            .Val => try writer.writeAll("Val"),
            .Var => try writer.writeAll("Var"),
            .If => try writer.writeAll("If"),
            .Else => try writer.writeAll("Else"),
            .Not => try writer.writeAll("Not"),
            .And => try writer.writeAll("And"),
            .Or => try writer.writeAll("Or"),
            .LeftParenthesis => try writer.writeAll("LeftParenthesis"),
            .RightParenthesis => try writer.writeAll("RightParenthesis"),
            .LeftBrace => try writer.writeAll("LeftBrace"),
            .RightBrace => try writer.writeAll("RightBrace"),
            .Assign => try writer.writeAll("Assign"),
            .Colon => try writer.writeAll("Colon"),
            .Semicolon => try writer.writeAll("Semicolon"),
            .Plus => try writer.writeAll("Plus"),
            .Minus => try writer.writeAll("Minus"),
            .Asterisk => try writer.writeAll("Asterisk"),
            .Slash => try writer.writeAll("Slash"),
            .Comma => try writer.writeAll("Comma"),
            .Identifier => |lexeme| try writer.print("Identifier(\"{s}\")", .{lexeme}),
            .IntLiteral => |value| try writer.print("IntLiteral({})", .{value}),
            .RealLiteral => |value| try writer.print("RealLiteral({})", .{value}),
            .BooleanLiteral => |value| try writer.print("BooleanLiteral({})", .{value}),
            .EndOfFile => try writer.writeAll("EndOfFile"),
            .Error => |err| try writer.print("Error(\"{s}\")", .{err.message}),
        }

        try writer.writeAll(")");
    }
};
