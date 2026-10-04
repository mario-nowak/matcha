const std = @import("std");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const tokens = @import("token.zig");
const TokenKind = tokens.TokenKind;
const Token = tokens.Token;

pub const Lexer = struct {
    source: []const u8,
    line: usize,
    column: usize,
    offset_in_source: usize,
    offset_in_token: u32,
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,

    pub fn init(source: []const u8, arena: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) Lexer {
        return .{
            .source = source,
            .arena = arena,
            .diagnostic_store = diagnostic_store,
            .line = 1,
            .column = 1,
            .offset_in_source = 0,
            .offset_in_token = 0,
        };
    }

    pub fn next(self: *Lexer) CompileError!Token {
        self.skipTrivia();

        if (self.done()) {
            return .{
                .line = self.line,
                .column = self.column,
                .offset_in_source = self.offset_in_source,
                .length_in_source = 0,
                .kind = .EndOfFile,
            };
        }

        const current_character = self.source[self.offset_in_source];
        if (current_character == '"') {
            return self.lexStringLiteral();
        }
        if (isAlphabetic(current_character)) {
            return self.lexKeywordOrIdentifier();
        }
        if (isNumeric(current_character)) {
            return self.lexNumericLiteral();
        }

        return self.lexOperator();
    }

    pub fn peek(self: *Lexer) CompileError!Token {
        const line_before_next = self.line;
        const column_before_next = self.column;
        const offset_in_source_before_next = self.offset_in_source;

        const next_token = try self.next();

        self.line = line_before_next;
        self.column = column_before_next;
        self.offset_in_source = offset_in_source_before_next;

        return next_token;
    }

    pub fn done(self: *Lexer) bool {
        return self.offset_in_source >= self.source.len;
    }

    fn emitError(
        self: *Lexer,
        line: usize,
        column: usize,
        offset_in_source: usize,
        len_in_source: u32,
        message: []const u8,
    ) CompileError {
        self.diagnostic_store.emitErrorFromSpan(.{
            .line = line,
            .column = column,
            .byte_offset = offset_in_source,
            .byte_len = len_in_source,
        }, message) catch return error.OutOfMemory;
        return error.DiagnosticsEmitted;
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
        self.offset_in_token = 0;
        for (self.source[self.offset_in_source..self.source.len]) |character| {
            if (!isAlphanumeric(character)) {
                break;
            }
            self.offset_in_token += 1;
        }

        const alphanumeric = self.source[self.offset_in_source .. self.offset_in_source + self.offset_in_token];
        var token_kind = asBooleanLiteral(alphanumeric);
        if (token_kind == null) {
            token_kind = asKeyword(alphanumeric);
        }
        if (token_kind == null) {
            token_kind = .{ .Identifier = alphanumeric };
        }

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offset_in_source = self.offset_in_source,
            .length_in_source = self.offset_in_token,
            .kind = token_kind.?,
        };

        self.column += self.offset_in_token;
        self.offset_in_source += self.offset_in_token;

        return token;
    }

    fn lexNumericLiteral(self: *Lexer) CompileError!Token {
        self.offset_in_token = 0;
        for (self.source[self.offset_in_source..self.source.len]) |character| {
            if (!isNumeric(character)) {
                break;
            }
            self.offset_in_token += 1;
        }

        const numeric = self.source[self.offset_in_source .. self.offset_in_source + self.offset_in_token];
        // The lexer only accepts digits, so overflow is the only way parsing can fail.
        const value = std.fmt.parseInt(i64, numeric, 10) catch return self.emitError(
            self.line,
            self.column,
            self.offset_in_source,
            self.offset_in_token,
            "integer literal is too large for int, the maximum is 9223372036854775807",
        );

        const token = Token{
            .line = self.line,
            .column = self.column,
            .offset_in_source = self.offset_in_source,
            .length_in_source = self.offset_in_token,
            .kind = .{ .IntLiteral = value },
        };

        self.column += self.offset_in_token;
        self.offset_in_source += self.offset_in_token;

        return token;
    }

    fn lexStringLiteral(self: *Lexer) CompileError!Token {
        const start_line = self.line;
        const start_column = self.column;
        const start_offset = self.offset_in_source;
        var content = std.ArrayList(u8){};

        // Skip the opening quote
        self.offset_in_source += 1;
        self.column += 1;

        while (!self.done()) {
            const character = self.source[self.offset_in_source];
            if (character == '"') {
                // Skip the closing quote
                self.offset_in_source += 1;
                self.column += 1;

                const total_length: u32 = @intCast(self.offset_in_source - start_offset);
                const decoded_content = try content.toOwnedSlice(self.arena);

                return Token{
                    .line = start_line,
                    .column = start_column,
                    .offset_in_source = start_offset,
                    .length_in_source = total_length,
                    .kind = .{ .StringLiteral = decoded_content },
                };
            }

            if (character == '\\') {
                self.offset_in_source += 1;
                self.column += 1;

                if (self.done()) {
                    const total_length: u32 = @intCast(self.offset_in_source - start_offset);
                    return self.emitError(
                        start_line,
                        start_column,
                        start_offset,
                        total_length,
                        "unterminated string literal",
                    );
                }

                const escaped_character = self.source[self.offset_in_source];
                const decoded_character: u8 = switch (escaped_character) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '"' => '"',
                    '\\' => '\\',
                    else => {
                        self.offset_in_source += 1;
                        self.column += 1;
                        const total_length: u32 = @intCast(self.offset_in_source - start_offset);
                        return self.emitError(
                            start_line,
                            start_column,
                            start_offset,
                            total_length,
                            "unknown string escape sequence",
                        );
                    },
                };
                try content.append(self.arena, decoded_character);
                self.offset_in_source += 1;
                self.column += 1;
                continue;
            }

            try content.append(self.arena, character);
            self.offset_in_source += 1;
            self.column += 1;
        }

        const total_length: u32 = @intCast(self.offset_in_source - start_offset);
        return self.emitError(
            start_line,
            start_column,
            start_offset,
            total_length,
            "unterminated string literal",
        );
    }

    fn lexOperator(self: *Lexer) CompileError!Token {
        const character = self.source[self.offset_in_source];
        if (self.offset_in_source + 1 < self.source.len) {
            const next_character = self.source[self.offset_in_source + 1];
            const multi_character_kind: ?TokenKind = switch (character) {
                '=' => if (next_character == '=') .EqualEqual else if (next_character == '>') .FatArrow else null,
                '+' => if (next_character == '=') .PlusAssign else null,
                '-' => if (next_character == '=') .MinusAssign else null,
                '*' => if (next_character == '=') .AsteriskAssign else null,
                '!' => if (next_character == '=') .NotEqual else null,
                '<' => if (next_character == '=') .LessThanOrEqual else null,
                '>' => if (next_character == '=') .GreaterThanOrEqual else null,
                else => null,
            };

            if (multi_character_kind) |kind| {
                const token = Token{
                    .line = self.line,
                    .column = self.column,
                    .offset_in_source = self.offset_in_source,
                    .length_in_source = 2,
                    .kind = kind,
                };

                self.offset_in_source += 2;
                self.column += 2;

                return token;
            }
        }

        const line = self.line;
        const column = self.column;
        const offset_in_source = self.offset_in_source;

        const kind: ?TokenKind = switch (character) {
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
            else => null,
        };

        self.offset_in_source += 1;
        self.column += 1;

        if (kind) |resolved_kind| {
            return Token{
                .line = line,
                .column = column,
                .offset_in_source = offset_in_source,
                .length_in_source = 1,
                .kind = resolved_kind,
            };
        }

        return self.emitError(line, column, offset_in_source, 1, "unrecognized character");
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
        if (std.mem.eql(u8, alphanumeric, "for")) return .For;
        if (std.mem.eql(u8, alphanumeric, "in")) return .In;
        if (std.mem.eql(u8, alphanumeric, "return")) return .Return;
        if (std.mem.eql(u8, alphanumeric, "structure")) return .Structure;
        if (std.mem.eql(u8, alphanumeric, "union")) return .Union;
        return null;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.done()) {
            const character = self.source[self.offset_in_source];
            if (character == ' ' or character == '\t' or character == '\r') {
                self.offset_in_source += 1;
                self.column += 1;
            } else if (character == '\n') {
                self.offset_in_source += 1;
                self.line += 1;
                self.column = 1;
            } else {
                break;
            }
        }
    }

    fn skipTrivia(self: *Lexer) void {
        while (true) {
            self.skipWhitespace();
            if (!self.skipComment()) break;
        }
    }

    fn skipComment(self: *Lexer) bool {
        if (self.offset_in_source + 1 >= self.source.len) {
            return false;
        }

        if (self.source[self.offset_in_source] != '/' or self.source[self.offset_in_source + 1] != '/') {
            return false;
        }

        self.offset_in_source += 2;
        self.column += 2;

        while (!self.done() and self.source[self.offset_in_source] != '\n') {
            self.offset_in_source += 1;
            self.column += 1;
        }

        return true;
    }
};
