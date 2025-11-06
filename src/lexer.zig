const std = @import("std");

pub const TokenType = union(enum) {
    //
    Let,
    LeftParenthesis,
    RightParenthesis,
    Equal,
    Colon,
    Semicolon,
    Plus,
    Minus,
    Asterisk,
    Slash,
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
    type: TokenType,

    pub fn format(
        self: Token,
        writer: anytype,
    ) !void {
        try writer.print("Token(line={}, col={}, type=", .{ self.line, self.column });

        switch (self.type) {
            .Let => try writer.writeAll("Let"),
            .LeftParenthesis => try writer.writeAll("LeftParenthesis"),
            .RightParenthesis => try writer.writeAll("RightParenthesis"),
            .Equal => try writer.writeAll("Equal"),
            .Colon => try writer.writeAll("Colon"),
            .Semicolon => try writer.writeAll("Semicolon"),
            .Plus => try writer.writeAll("Plus"),
            .Minus => try writer.writeAll("Minus"),
            .Asterisk => try writer.writeAll("Asterisk"),
            .Slash => try writer.writeAll("Slash"),
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

pub const Lexer = struct {
    source: []const u8,
    line: usize,
    column: usize,
    offsetInSource: usize,
    offsetInToken: u32,
    allocator: std.mem.Allocator,

    pub fn init(source: []const u8, alloctor: std.mem.Allocator) Lexer {
        return .{
            .source = source,
            .allocator = alloctor,
            .line = 1,
            .column = 1,
            .offsetInSource = 0,
            .offsetInToken = 0,
        };
    }

    pub fn deinit(self: *Lexer) void {
        _ = self;
    }

    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();

        if (self.done()) {
            return .{
                .line = self.line,
                .column = self.column,
                .offsetInSource = self.offsetInSource,
                .lenInSource = 0,
                .type = .EndOfFile,
            };
        }

        const currentCharacter = self.source[self.offsetInSource];
        if (isAlphabetic(currentCharacter)) {
            return self.lexKeywordOrIdentifier();
        }
        if (isNumeric(currentCharacter)) {
            return self.lexNumericLiteral();
        }

        return self.lexOperator();
    }

    pub fn done(self: *Lexer) bool {
        return self.offsetInSource >= self.source.len;
    }

    fn isAlphabetic(character: u8) bool {
        return (character >= 'a' and character <= 'z') or (character >= 'A' and character <= 'Z') or (character == '_');
    }

    fn isNumeric(character: u8) bool {
        return character >= '0' and character <= '9';
    }

    fn isAlphanumeric(character: u8) bool {
        return isAlphabetic(character) or isNumeric(character);
    }

    fn lexKeywordOrIdentifier(self: *Lexer) Token {
        self.offsetInToken = 0;
        for (self.source[self.offsetInSource..self.source.len]) |character| {
            if (!isAlphanumeric(character)) {
                break;
            }
            self.offsetInToken += 1;
        }

        const alphanumeric = self.source[self.offsetInSource .. self.offsetInSource + self.offsetInToken];
        var tokenType = asKeyword(alphanumeric);
        if (tokenType == null) {
            tokenType = .{ .Identifier = alphanumeric };
        }

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offsetInSource = self.offsetInSource,
            .lenInSource = self.offsetInToken,
            .type = tokenType.?,
        };

        self.column += self.offsetInToken;
        self.offsetInSource += self.offsetInToken;

        return token;
    }

    fn lexNumericLiteral(self: *Lexer) Token {
        self.offsetInToken = 0;
        for (self.source[self.offsetInSource..self.source.len]) |character| {
            if (!isNumeric(character)) {
                break;
            }
            self.offsetInToken += 1;
        }

        const numeric = self.source[self.offsetInSource .. self.offsetInSource + self.offsetInToken];

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offsetInSource = self.offsetInSource,
            .lenInSource = self.offsetInToken,
            .type = .{ .IntLiteral = std.fmt.parseInt(i64, numeric, 10) catch 0 },
        };

        self.column += self.offsetInToken;
        self.offsetInSource += self.offsetInToken;

        return token;
    }

    fn lexOperator(self: *Lexer) Token {
        self.offsetInToken = 0;
        for (self.source[self.offsetInSource..self.source.len]) |character| {
            _ = switch (character) {
                '=' => .{},
                else => break,
            };
            self.offsetInToken += 1;
        }

        if (self.offsetInToken > 0) {
            // todo check for multi character operators
        }

        const character = self.source[self.offsetInSource];

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offsetInSource = self.offsetInSource,
            .lenInSource = 1,
            .type = switch (character) {
                '=' => .Equal,
                '(' => .LeftParenthesis,
                ')' => .RightParenthesis,
                ':' => .Colon,
                ';' => .Semicolon,
                '+' => .Plus,
                '-' => .Minus,
                '*' => .Asterisk,
                '/' => .Slash,
                else => .{ .Error = .{ .message = "Unrecognized character" } },
            },
        };

        self.offsetInSource += 1;
        self.column += 1;

        return token;
    }

    fn asKeyword(alphanumeric: []const u8) ?TokenType {
        if (std.mem.eql(u8, alphanumeric, "let")) return .Let;
        return null;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.done()) {
            const character = self.source[self.offsetInSource];
            if (character == ' ' or character == '\t' or character == '\r') {
                self.offsetInSource += 1;
                self.column += 1;
            } else if (character == '\n') {
                self.offsetInSource += 1;
                self.line += 1;
                self.column = 1;
            } else {
                break;
            }
        }
    }
};
