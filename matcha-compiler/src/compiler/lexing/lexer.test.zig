const std = @import("std");
const expect = @import("testing").expect;
const setupLexerPipeline = @import("test_helpers.zig").setupLexerPipeline;
const collectTokens = @import("test_helpers.zig").collectTokens;

test "lexer tokenizes boolean keywords and comparison operators" {
    const source = "not true and false or value == other != third <= fourth >= fifth < sixth > seventh =";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Not },
        .{ .kind = .{ .BooleanLiteral = true } },
        .{ .kind = .And },
        .{ .kind = .{ .BooleanLiteral = false } },
        .{ .kind = .Or },
        .{ .kind = .{ .Identifier = "value" } },
        .{ .kind = .EqualEqual },
        .{ .kind = .{ .Identifier = "other" } },
        .{ .kind = .NotEqual },
        .{ .kind = .{ .Identifier = "third" } },
        .{ .kind = .LessThanOrEqual },
        .{ .kind = .{ .Identifier = "fourth" } },
        .{ .kind = .GreaterThanOrEqual },
        .{ .kind = .{ .Identifier = "fifth" } },
        .{ .kind = .LessThan },
        .{ .kind = .{ .Identifier = "sixth" } },
        .{ .kind = .GreaterThan },
        .{ .kind = .{ .Identifier = "seventh" } },
        .{ .kind = .Assign },
        .{ .kind = .EndOfFile },
    });
}

test "lexer keeps keyword prefixes inside identifiers" {
    const source = "notable android orbit iffy elsewise value";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "notable" } },
        .{ .kind = .{ .Identifier = "android" } },
        .{ .kind = .{ .Identifier = "orbit" } },
        .{ .kind = .{ .Identifier = "iffy" } },
        .{ .kind = .{ .Identifier = "elsewise" } },
        .{ .kind = .{ .Identifier = "value" } },
        .{ .kind = .EndOfFile },
    });
}

test "lexer distinguishes assign from equality operators" {
    const source = "= += -= *= => == != < <= > >= [ ]";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Assign },
        .{ .kind = .PlusAssign },
        .{ .kind = .MinusAssign },
        .{ .kind = .AsteriskAssign },
        .{ .kind = .FatArrow },
        .{ .kind = .EqualEqual },
        .{ .kind = .NotEqual },
        .{ .kind = .LessThan },
        .{ .kind = .LessThanOrEqual },
        .{ .kind = .GreaterThan },
        .{ .kind = .GreaterThanOrEqual },
        .{ .kind = .LeftBracket },
        .{ .kind = .RightBracket },
        .{ .kind = .EndOfFile },
    });
}

test "lexer tokenizes match keyword and arrows" {
    const source =
        \\match value { true => 1, else => 0 }
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Match },
        .{ .kind = .{ .Identifier = "value" } },
        .{ .kind = .LeftBrace },
        .{ .kind = .{ .BooleanLiteral = true } },
        .{ .kind = .FatArrow },
        .{ .kind = .{ .IntLiteral = 1 } },
        .{ .kind = .Comma },
        .{ .kind = .Else },
        .{ .kind = .FatArrow },
        .{ .kind = .{ .IntLiteral = 0 } },
        .{ .kind = .RightBrace },
        .{ .kind = .EndOfFile },
    });
}

test "lexer tokenizes for-in keywords" {
    const source =
        \\for value in items { continue; }
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .For },
        .{ .kind = .{ .Identifier = "value" } },
        .{ .kind = .In },
        .{ .kind = .{ .Identifier = "items" } },
        .{ .kind = .LeftBrace },
        .{ .kind = .Continue },
        .{ .kind = .Semicolon },
        .{ .kind = .RightBrace },
        .{ .kind = .EndOfFile },
    });
}

test "lexer keeps item as an identifier" {
    const source =
        \\item structure
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .Identifier = "item" } },
        .{ .kind = .Structure },
        .{ .kind = .EndOfFile },
    });
}

test "lexer tokenizes plain string literals" {
    const source =
        \\val greeting = "hello world";
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Val },
        .{ .kind = .{ .Identifier = "greeting" } },
        .{ .kind = .Assign },
        .{ .kind = .{ .StringLiteral = "hello world" } },
        .{ .kind = .Semicolon },
        .{ .kind = .EndOfFile },
    });
}

test "lexer captures string literal content" {
    const source =
        \\"hello"
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "hello" } },
        .{ .kind = .EndOfFile },
    });
}

test "lexer decodes string literal escapes" {
    const source = "\"line\\nquote: \\\" slash: \\\\ tab: \\t\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "line\nquote: \" slash: \\ tab: \t" } },
        .{ .kind = .EndOfFile },
    });
}

test "lexer tokenizes multiple strings in sequence" {
    const source =
        \\"first" "second"
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .StringLiteral = "first" } },
        .{ .kind = .{ .StringLiteral = "second" } },
        .{ .kind = .EndOfFile },
    });
}

test "lexer emits a diagnostic for unterminated string literals" {
    const source = "\"hello";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const result = lexerPipeline.lexer.next();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(lexerPipeline.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "unterminated string literal" },
    });
}

test "lexer emits a diagnostic for unrecognized characters" {
    const source = "@";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const result = lexerPipeline.lexer.next();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(lexerPipeline.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "unrecognized character" },
    });
}

test "lexer skips line comments" {
    const source =
        \\// comment before code
        \\val answer = 42; // trailing comment
        \\var next = answer;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Val },
        .{ .kind = .{ .Identifier = "answer" } },
        .{ .kind = .Assign },
        .{ .kind = .{ .IntLiteral = 42 } },
        .{ .kind = .Semicolon },
        .{ .kind = .Var },
        .{ .kind = .{ .Identifier = "next" } },
        .{ .kind = .Assign },
        .{ .kind = .{ .Identifier = "answer" } },
        .{ .kind = .Semicolon },
        .{ .kind = .EndOfFile },
    });
}

test "lexer skips consecutive line comments" {
    const source =
        \\val first = 1;
        \\// first comment
        \\// second comment
        \\val second = 2;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexerPipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexerPipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .Val },
        .{ .kind = .{ .Identifier = "first" } },
        .{ .kind = .Assign },
        .{ .kind = .{ .IntLiteral = 1 } },
        .{ .kind = .Semicolon },
        .{ .kind = .Val },
        .{ .kind = .{ .Identifier = "second" } },
        .{ .kind = .Assign },
        .{ .kind = .{ .IntLiteral = 2 } },
        .{ .kind = .Semicolon },
        .{ .kind = .EndOfFile },
    });
}
