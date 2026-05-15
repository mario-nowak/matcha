const std = @import("std");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");

const TokenTag = std.meta.Tag(lexing.TokenKind);

const LexedSource = struct {
    diagnostic_store: diagnostics.DiagnosticStore,
    lexer: lexing.Lexer,

    fn init(source: []const u8) LexedSource {
        var lexed: LexedSource = undefined;
        lexed.diagnostic_store = diagnostics.DiagnosticStore.init(std.heap.page_allocator);
        lexed.lexer = lexing.Lexer.init(source, std.heap.page_allocator, &lexed.diagnostic_store);
        return lexed;
    }

    fn deinit(self: *LexedSource) void {
        self.lexer.deinit();
        self.diagnostic_store.deinit();
    }
};

fn expectTokenTag(token: lexing.Token, expected: TokenTag) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(token.kind));
}

fn expectTokenSequence(source: []const u8, expected_tags: []const TokenTag) !void {
    var lexed = LexedSource.init(source);
    defer lexed.deinit();

    for (expected_tags) |expected_tag| {
        try expectTokenTag(try lexed.lexer.next(), expected_tag);
    }
}

fn expectLexDiagnostic(source: []const u8, expected_message: []const u8) !void {
    var lexed = LexedSource.init(source);
    defer lexed.deinit();

    try std.testing.expectError(error.DiagnosticsEmitted, lexed.lexer.next());

    const diagnostic_items = lexed.diagnostic_store.items();
    try std.testing.expectEqual(@as(usize, 1), diagnostic_items.len);
    try std.testing.expectEqualStrings(expected_message, diagnostic_items[0].message);
}

test "lexer tokenizes boolean keywords and comparison operators" {
    const source = "not true and false or value == other != third <= fourth >= fifth < sixth > seventh =";

    const expected_tags = [_]TokenTag{
        .Not,
        .BooleanLiteral,
        .And,
        .BooleanLiteral,
        .Or,
        .Identifier,
        .EqualEqual,
        .Identifier,
        .NotEqual,
        .Identifier,
        .LessThanOrEqual,
        .Identifier,
        .GreaterThanOrEqual,
        .Identifier,
        .LessThan,
        .Identifier,
        .GreaterThan,
        .Identifier,
        .Assign,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer keeps keyword prefixes inside identifiers" {
    const source = "notable android orbit iffy elsewise value";

    const expected_tags = [_]TokenTag{
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer distinguishes assign from equality operators" {
    const source = "= += -= *= => == != < <= > >= [ ]";

    const expected_tags = [_]TokenTag{
        .Assign,
        .PlusAssign,
        .MinusAssign,
        .AsteriskAssign,
        .FatArrow,
        .EqualEqual,
        .NotEqual,
        .LessThan,
        .LessThanOrEqual,
        .GreaterThan,
        .GreaterThanOrEqual,
        .LeftBracket,
        .RightBracket,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer tokenizes match keyword and arrows" {
    const source =
        \\match value { true => 1, else => 0 }
    ;

    const expected_tags = [_]TokenTag{
        .Match,
        .Identifier,
        .LeftBrace,
        .BooleanLiteral,
        .FatArrow,
        .IntLiteral,
        .Comma,
        .Else,
        .FatArrow,
        .IntLiteral,
        .RightBrace,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer tokenizes for-in keywords" {
    const source =
        \\for value in items { continue; }
    ;

    const expected_tags = [_]TokenTag{
        .For,
        .Identifier,
        .In,
        .Identifier,
        .LeftBrace,
        .Continue,
        .Semicolon,
        .RightBrace,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer keeps item as an identifier" {
    const source =
        \\item structure
    ;

    const expected_tags = [_]TokenTag{
        .Identifier,
        .Structure,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer tokenizes plain string literals" {
    const source =
        \\val greeting = "hello world";
    ;

    const expected_tags = [_]TokenTag{
        .Val,
        .Identifier,
        .Assign,
        .StringLiteral,
        .Semicolon,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer captures string literal content" {
    const source =
        \\"hello"
    ;

    var lexed = LexedSource.init(source);
    defer lexed.deinit();

    const token = try lexed.lexer.next();
    try std.testing.expectEqualStrings("hello", token.kind.StringLiteral);
}

test "lexer decodes string literal escapes" {
    const source = "\"line\\nquote: \\\" slash: \\\\ tab: \\t\"";

    var lexed = LexedSource.init(source);
    defer lexed.deinit();

    const token = try lexed.lexer.next();
    try expectTokenTag(token, .StringLiteral);
    try std.testing.expectEqualStrings("line\nquote: \" slash: \\ tab: \t", token.kind.StringLiteral);
}

test "lexer tokenizes multiple strings in sequence" {
    const source =
        \\"first" "second"
    ;

    var lexed = LexedSource.init(source);
    defer lexed.deinit();

    const first = try lexed.lexer.next();
    const second = try lexed.lexer.next();
    try expectTokenTag(first, .StringLiteral);
    try std.testing.expectEqualStrings("first", first.kind.StringLiteral);
    try expectTokenTag(second, .StringLiteral);
    try std.testing.expectEqualStrings("second", second.kind.StringLiteral);
}

test "lexer emits a diagnostic for unterminated string literals" {
    const source = "\"hello";

    try expectLexDiagnostic(source, "unterminated string literal");
}

test "lexer emits a diagnostic for unrecognized characters" {
    const source = "@";

    try expectLexDiagnostic(source, "unrecognized character");
}

test "lexer skips line comments" {
    const source =
        \\// comment before code
        \\val answer = 42; // trailing comment
        \\var next = answer;
    ;

    const expected_tags = [_]TokenTag{
        .Val,
        .Identifier,
        .Assign,
        .IntLiteral,
        .Semicolon,
        .Var,
        .Identifier,
        .Assign,
        .Identifier,
        .Semicolon,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}

test "lexer skips consecutive line comments" {
    const source =
        \\val first = 1;
        \\// first comment
        \\// second comment
        \\val second = 2;
    ;

    const expected_tags = [_]TokenTag{
        .Val,
        .Identifier,
        .Assign,
        .IntLiteral,
        .Semicolon,
        .Val,
        .Identifier,
        .Assign,
        .IntLiteral,
        .Semicolon,
        .EndOfFile,
    };
    try expectTokenSequence(source, &expected_tags);
}
