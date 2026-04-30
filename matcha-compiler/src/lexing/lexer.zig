const std = @import("std");
const tokens = @import("token.zig");
const TokenKind = tokens.TokenKind;
const Token = tokens.Token;

pub const Lexer = struct {
    source: []const u8,
    line: usize,
    column: usize,
    offsetInSource: usize,
    offsetInToken: u32,
    allocator: std.mem.Allocator,

    pub fn init(source: []const u8, allocator: std.mem.Allocator) Lexer {
        return .{
            .source = source,
            .allocator = allocator,
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
                .kind = .EndOfFile,
            };
        }

        const currentCharacter = self.source[self.offsetInSource];
        if (currentCharacter == '"') {
            return self.lexStringLiteral();
        }
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
            .kind = tokenType.?,
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
            .kind = .{ .IntLiteral = std.fmt.parseInt(i64, numeric, 10) catch 0 },
        };

        self.column += self.offsetInToken;
        self.offsetInSource += self.offsetInToken;

        return token;
    }

    fn lexStringLiteral(self: *Lexer) Token {
        const start_line = self.line;
        const start_column = self.column;
        const start_offset = self.offsetInSource;

        // Skip the opening quote
        self.offsetInSource += 1;
        self.column += 1;

        while (!self.done()) {
            const character = self.source[self.offsetInSource];
            if (character == '"') {
                const content = self.source[start_offset + 1 .. self.offsetInSource];

                // Skip the closing quote
                self.offsetInSource += 1;
                self.column += 1;

                const total_length: u32 = @intCast(self.offsetInSource - start_offset);

                return Token{
                    .line = start_line,
                    .column = start_column,
                    .offsetInSource = start_offset,
                    .lenInSource = total_length,
                    .kind = .{ .StringLiteral = content },
                };
            }
            self.offsetInSource += 1;
            self.column += 1;
        }

        const total_length: u32 = @intCast(self.offsetInSource - start_offset);

        return Token{
            .line = start_line,
            .column = start_column,
            .offsetInSource = start_offset,
            .lenInSource = total_length,
            .kind = .{ .Error = .{ .message = "Unterminated string literal" } },
        };
    }

    fn lexOperator(self: *Lexer) Token {
        const character = self.source[self.offsetInSource];
        if (self.offsetInSource + 1 < self.source.len) {
            const nextCharacter = self.source[self.offsetInSource + 1];
            const multiCharacterKind: ?TokenKind = switch (character) {
                '=' => if (nextCharacter == '=') .EqualEqual else if (nextCharacter == '>') .FatArrow else null,
                '!' => if (nextCharacter == '=') .NotEqual else null,
                '<' => if (nextCharacter == '=') .LessThanOrEqual else null,
                '>' => if (nextCharacter == '=') .GreaterThanOrEqual else null,
                else => null,
            };

            if (multiCharacterKind) |kind| {
                const token = Token{
                    .line = self.line,
                    .column = self.column,
                    .offsetInSource = self.offsetInSource,
                    .lenInSource = 2,
                    .kind = kind,
                };

                self.offsetInSource += 2;
                self.column += 2;

                return token;
            }
        }

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offsetInSource = self.offsetInSource,
            .lenInSource = 1,
            .kind = switch (character) {
                '=' => .Assign,
                '(' => .LeftParenthesis,
                ')' => .RightParenthesis,
                '{' => .LeftBrace,
                '}' => .RightBrace,
                '[' => .LeftBracket,
                ']' => .RightBracket,
                ':' => .Colon,
                ';' => .Semicolon,
                '+' => .Plus,
                '-' => .Minus,
                '*' => .Asterisk,
                '/' => .Slash,
                '<' => .LessThan,
                '>' => .GreaterThan,
                ',' => .Comma,
                '.' => .Dot,
                else => .{ .Error = .{ .message = "Unrecognized character" } },
            },
        };

        self.offsetInSource += 1;
        self.column += 1;

        return token;
    }

    fn asBooleanLiteral(alphanumeric: []const u8) ?TokenKind {
        if (std.mem.eql(u8, alphanumeric, "true")) return .{ .BooleanLiteral = true };
        if (std.mem.eql(u8, alphanumeric, "false")) return .{ .BooleanLiteral = false };
        return null;
    }

    fn asKeyword(alphanumeric: []const u8) ?TokenKind {
        if (std.mem.eql(u8, alphanumeric, "val")) return .Val;
        if (std.mem.eql(u8, alphanumeric, "var")) return .Var;
        if (std.mem.eql(u8, alphanumeric, "if")) return .If;
        if (std.mem.eql(u8, alphanumeric, "else")) return .Else;
        if (std.mem.eql(u8, alphanumeric, "match")) return .Match;
        if (std.mem.eql(u8, alphanumeric, "not")) return .Not;
        if (std.mem.eql(u8, alphanumeric, "and")) return .And;
        if (std.mem.eql(u8, alphanumeric, "or")) return .Or;
        if (std.mem.eql(u8, alphanumeric, "loop")) return .Loop;
        if (std.mem.eql(u8, alphanumeric, "leave")) return .Leave;
        if (std.mem.eql(u8, alphanumeric, "continue")) return .Continue;
        if (std.mem.eql(u8, alphanumeric, "while")) return .While;
        if (std.mem.eql(u8, alphanumeric, "item")) return .Item;
        if (std.mem.eql(u8, alphanumeric, "return")) return .Return;
        if (std.mem.eql(u8, alphanumeric, "structure")) return .Structure;
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
