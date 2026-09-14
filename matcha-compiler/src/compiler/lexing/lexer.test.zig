const std = @import("std");
const expect = @import("testing").expect;
const setupLexerPipeline = @import("test_helpers.zig").setupLexerPipeline;
const collectTokens = @import("test_helpers.zig").collectTokens;

test "Lexer > next: tokenizes boolean keywords" {
    const source = "not true and false or";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Not },
        .{ .kind = .{ .BooleanLiteral = true } },
        .{ .kind = .And },
        .{ .kind = .{ .BooleanLiteral = false } },
        .{ .kind = .Or },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: keeps keyword prefixes inside identifiers" {
    const source = "notable android orbit iffy elsewise";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "notable" } },
        .{ .kind = .{ .Identifier = "android" } },
        .{ .kind = .{ .Identifier = "orbit" } },
        .{ .kind = .{ .Identifier = "iffy" } },
        .{ .kind = .{ .Identifier = "elsewise" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: distinguishes assignment from equality" {
    const source = "= ==";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Assign },
        .{ .kind = .EqualEqual },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes compound assignment operators" {
    const source = "+= -= *=";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .PlusAssign },
        .{ .kind = .MinusAssign },
        .{ .kind = .AsteriskAssign },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes comparison operators" {
    const source = "== != < <= > >=";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .EqualEqual },
        .{ .kind = .NotEqual },
        .{ .kind = .LessThan },
        .{ .kind = .LessThanOrEqual },
        .{ .kind = .GreaterThan },
        .{ .kind = .GreaterThanOrEqual },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: distinguishes a fat arrow from assignment and equality" {
    const source = "=> = ==";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .FatArrow },
        .{ .kind = .Assign },
        .{ .kind = .EqualEqual },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes brackets" {
    const source = "[]";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .LeftBracket },
        .{ .kind = .RightBracket },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes match keywords" {
    const source = "match else";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Match },
        .{ .kind = .Else },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes for-in keywords" {
    const source = "for in";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .For },
        .{ .kind = .In },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes the continue keyword" {
    const source = "continue";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Continue },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: keeps item as an identifier" {
    const source = "item";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "item" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes the structure keyword" {
    const source = "structure";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Structure },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes binding keywords" {
    const source = "val var";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Val },
        .{ .kind = .Var },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes braces and separators" {
    const source = "{},;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .LeftBrace },
        .{ .kind = .RightBrace },
        .{ .kind = .Comma },
        .{ .kind = .Semicolon },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: captures integer literal values" {
    const source = "0 1 2 42";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .IntLiteral = 0 } },
        .{ .kind = .{ .IntLiteral = 1 } },
        .{ .kind = .{ .IntLiteral = 2 } },
        .{ .kind = .{ .IntLiteral = 42 } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: preserves spaces inside string literals" {
    const source = "\"hello world\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "hello world" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: captures string literal content" {
    const source = "\"hello\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "hello" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: decodes string literal escapes" {
    const source = "\"line\\nquote: \\\" slash: \\\\ tab: \\t\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "line\nquote: \" slash: \\ tab: \t" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: tokenizes multiple strings in sequence" {
    const source =
        \\"first" "second"
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "first" } },
        .{ .kind = .{ .StringLiteral = "second" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: emits a diagnostic when a string is unterminated" {
    const source = "\"hello";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const result = lexer_pipeline.lexer.next();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(lexer_pipeline.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "unterminated string literal" },
    });
}

test "Lexer > next: emits a diagnostic when a character is unrecognized" {
    const source = "@";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const result = lexer_pipeline.lexer.next();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(lexer_pipeline.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "unrecognized character" },
    });
}

test "Lexer > next: skips a comment before a token" {
    const source =
        \\// comment before code
        \\answer
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "answer" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: resumes tokenization after a trailing comment" {
    const source =
        \\answer // trailing comment
        \\next
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "answer" } },
        .{ .kind = .{ .Identifier = "next" } },
        .{ .kind = .EndOfFile },
    });
}

test "Lexer > next: skips consecutive line comments" {
    const source =
        \\first
        \\// first comment
        \\// second comment
        \\second
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "first" } },
        .{ .kind = .{ .Identifier = "second" } },
        .{ .kind = .EndOfFile },
    });
}
