const std = @import("std");
const lexing = @import("lexing");

const TokenTag = std.meta.Tag(lexing.TokenKind);

fn expectTokenTag(token: lexing.Token, expected: TokenTag) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(token.kind));
}

test "lexer tokenizes boolean keywords and comparison operators" {
    var lexer = lexing.Lexer.init(
        "not true and false or value == other != third <= fourth >= fifth < sixth > seventh =",
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer keeps keyword prefixes inside identifiers" {
    var lexer = lexing.Lexer.init(
        "notable android orbit iffy elsewise value",
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const expected_tags = [_]TokenTag{
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .Identifier,
        .EndOfFile,
    };

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer distinguishes assign from equality operators" {
    var lexer = lexing.Lexer.init(
        "= += -= *= => == != < <= > >= [ ]",
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer tokenizes match keyword and arrows" {
    var lexer = lexing.Lexer.init(
        \\match value { true => 1, else => 0 }
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer tokenizes for-in keywords" {
    var lexer = lexing.Lexer.init(
        \\for value in items { continue; }
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer tokenizes plain string literals" {
    var lexer = lexing.Lexer.init(
        \\val greeting = "hello world";
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const expected_tags = [_]TokenTag{
        .Val,
        .Identifier,
        .Assign,
        .StringLiteral,
        .Semicolon,
        .EndOfFile,
    };

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer captures string literal content" {
    var lexer = lexing.Lexer.init(
        \\"hello"
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const token = lexer.next();
    try std.testing.expectEqualStrings("hello", token.kind.StringLiteral);
}

test "lexer decodes string literal escapes" {
    var lexer = lexing.Lexer.init(
        "\"line\\nquote: \\\" slash: \\\\ tab: \\t\"",
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const token = lexer.next();
    try expectTokenTag(token, .StringLiteral);
    try std.testing.expectEqualStrings("line\nquote: \" slash: \\ tab: \t", token.kind.StringLiteral);
}

test "lexer tokenizes multiple strings in sequence" {
    var lexer = lexing.Lexer.init(
        \\"first" "second"
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const first = lexer.next();
    try expectTokenTag(first, .StringLiteral);
    try std.testing.expectEqualStrings("first", first.kind.StringLiteral);

    const second = lexer.next();
    try expectTokenTag(second, .StringLiteral);
    try std.testing.expectEqualStrings("second", second.kind.StringLiteral);
}

test "lexer skips line comments" {
    var lexer = lexing.Lexer.init(
        \\// comment before code
        \\val answer = 42; // trailing comment
        \\var next = answer;
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}

test "lexer skips consecutive line comments" {
    var lexer = lexing.Lexer.init(
        \\val first = 1;
        \\// first comment
        \\// second comment
        \\val second = 2;
    ,
        std.heap.page_allocator,
    );
    defer lexer.deinit();

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

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}
