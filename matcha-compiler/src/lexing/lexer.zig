const std = @import("std");
const token_module = @import("token.zig");
const TokenType = token_module.TokenType;
const Token = token_module.Token;

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

    pub fn peek(self: *Lexer) Token {
        const lineBeforeNext = self.line;
        const columnBeforeNext = self.column;
        const offsetInSourceBeforeNext = self.offsetInSource;

        const nextToken = self.next();

        self.line = lineBeforeNext;
        self.column = columnBeforeNext;
        self.offsetInSource = offsetInSourceBeforeNext;

        return nextToken;
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
        var tokenType = asBooleanLiteral(alphanumeric);
        if (tokenType == null) {
            tokenType = asKeyword(alphanumeric);
        }
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
                '{' => .LeftBrace,
                '}' => .RightBrace,
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

    fn asBooleanLiteral(alphanumeric: []const u8) ?TokenType {
        if (std.mem.eql(u8, alphanumeric, "true")) return .{ .BooleanLiteral = true };
        if (std.mem.eql(u8, alphanumeric, "false")) return .{ .BooleanLiteral = false };
        return null;
    }

    fn asKeyword(alphanumeric: []const u8) ?TokenType {
        if (std.mem.eql(u8, alphanumeric, "val")) return .Val;
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
