const std = @import("std");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const tokens = @import("token.zig");
const TokenKind = tokens.TokenKind;
const Token = tokens.Token;

pub const Lexer = struct {
    source: []const u8,
    module_id: diagnostics.ModuleId,
    line: usize,
    column: usize,
    offset_in_source: usize,
    offset_in_token: u32,
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,

    pub fn init(
        source: []const u8,
        module_id: diagnostics.ModuleId,
        arena: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
    ) Lexer {
        return .{
            .source = source,
            .module_id = module_id,
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
                .module_id = self.module_id,
                .line = self.line,
                .column = self.column,
                .offset_in_source = self.offset_in_source,
                .length_in_source = 0,
                .kind = .end_of_file,
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
            .module_id = self.module_id,
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
            token_kind = .{ .identifier = alphanumeric };
        }

        const token = Token{
            .module_id = self.module_id,
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
            .module_id = self.module_id,
            .line = self.line,
            .column = self.column,
            .offset_in_source = self.offset_in_source,
            .length_in_source = self.offset_in_token,
            .kind = .{ .int_literal = value },
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
                    .module_id = self.module_id,
                    .line = start_line,
                    .column = start_column,
                    .offset_in_source = start_offset,
                    .length_in_source = total_length,
                    .kind = .{ .string_literal = decoded_content },
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
                '=' => if (next_character == '=') .equal_equal else if (next_character == '>') .fat_arrow else null,
                '+' => if (next_character == '=') .plus_assign else null,
                '-' => if (next_character == '=') .minus_assign else null,
                '*' => if (next_character == '=') .asterisk_assign else null,
                '!' => if (next_character == '=') .not_equal else null,
                '<' => if (next_character == '=') .less_than_or_equal else null,
                '>' => if (next_character == '=') .greater_than_or_equal else null,
                else => null,
            };

            if (multi_character_kind) |kind| {
                const token = Token{
                    .module_id = self.module_id,
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
            '=' => .assign,
            '(' => .left_parenthesis,
            ')' => .right_parenthesis,
            '{' => .left_brace,
            '}' => .right_brace,
            '[' => .left_bracket,
            ']' => .right_bracket,
            ':' => .colon,
            ';' => .semicolon,
            '+' => .plus,
            '-' => .minus,
            '*' => .asterisk,
            '/' => .slash,
            '<' => .less_than,
            '>' => .greater_than,
            ',' => .comma,
            '.' => .dot,
            else => null,
        };

        self.offset_in_source += 1;
        self.column += 1;

        if (kind) |resolved_kind| {
            return Token{
                .module_id = self.module_id,
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
        if (std.mem.eql(u8, alphanumeric, "true")) return .{ .boolean_literal = true };
        if (std.mem.eql(u8, alphanumeric, "false")) return .{ .boolean_literal = false };
        return null;
    }

    fn asKeyword(alphanumeric: []const u8) ?TokenKind {
        if (std.mem.eql(u8, alphanumeric, "val")) return .val;
        if (std.mem.eql(u8, alphanumeric, "var")) return .@"var";
        if (std.mem.eql(u8, alphanumeric, "if")) return .@"if";
        if (std.mem.eql(u8, alphanumeric, "else")) return .@"else";
        if (std.mem.eql(u8, alphanumeric, "match")) return .match;
        if (std.mem.eql(u8, alphanumeric, "not")) return .not;
        if (std.mem.eql(u8, alphanumeric, "and")) return .@"and";
        if (std.mem.eql(u8, alphanumeric, "or")) return .@"or";
        if (std.mem.eql(u8, alphanumeric, "loop")) return .loop;
        if (std.mem.eql(u8, alphanumeric, "leave")) return .leave;
        if (std.mem.eql(u8, alphanumeric, "continue")) return .@"continue";
        if (std.mem.eql(u8, alphanumeric, "while")) return .@"while";
        if (std.mem.eql(u8, alphanumeric, "for")) return .@"for";
        if (std.mem.eql(u8, alphanumeric, "in")) return .in;
        if (std.mem.eql(u8, alphanumeric, "return")) return .@"return";
        if (std.mem.eql(u8, alphanumeric, "structure")) return .structure;
        if (std.mem.eql(u8, alphanumeric, "union")) return .@"union";
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
