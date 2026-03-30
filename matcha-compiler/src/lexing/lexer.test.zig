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
        "= == != < <= > >=",
        std.heap.page_allocator,
    );
    defer lexer.deinit();

    const expected_tags = [_]TokenTag{
        .Assign,
        .EqualEqual,
        .NotEqual,
        .LessThan,
        .LessThanOrEqual,
        .GreaterThan,
        .GreaterThanOrEqual,
        .EndOfFile,
    };

    for (expected_tags) |expected_tag| {
        try expectTokenTag(lexer.next(), expected_tag);
    }
}
