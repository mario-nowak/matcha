const std = @import("std");
const expect = @import("testing").expect;
const setupLexerPipeline = @import("testing").setupLexerPipeline;
const collectTokens = @import("testing").collectTokens;

test "Lexer > next: tokenizes boolean keywords" {
    const source = "not true and false or";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .not },
        .{ .kind = .{ .boolean_literal = true } },
        .{ .kind = .@"and" },
        .{ .kind = .{ .boolean_literal = false } },
        .{ .kind = .@"or" },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: keeps keyword prefixes inside identifiers" {
    const source = "notable android orbit iffy elsewise";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .identifier = "notable" } },
        .{ .kind = .{ .identifier = "android" } },
        .{ .kind = .{ .identifier = "orbit" } },
        .{ .kind = .{ .identifier = "iffy" } },
        .{ .kind = .{ .identifier = "elsewise" } },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: distinguishes assignment from equality" {
    const source = "= ==";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .assign },
        .{ .kind = .equal_equal },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes compound assignment operators" {
    const source = "+= -= *=";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .plus_assign },
        .{ .kind = .minus_assign },
        .{ .kind = .asterisk_assign },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes comparison operators" {
    const source = "== != < <= > >=";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .equal_equal },
        .{ .kind = .not_equal },
        .{ .kind = .less_than },
        .{ .kind = .less_than_or_equal },
        .{ .kind = .greater_than },
        .{ .kind = .greater_than_or_equal },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: distinguishes a fat arrow from assignment and equality" {
    const source = "=> = ==";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .fat_arrow },
        .{ .kind = .assign },
        .{ .kind = .equal_equal },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes brackets" {
    const source = "[]";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .left_bracket },
        .{ .kind = .right_bracket },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes match keywords" {
    const source = "match else";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .match },
        .{ .kind = .@"else" },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes for-in keywords" {
    const source = "for in";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .@"for" },
        .{ .kind = .in },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes the continue keyword" {
    const source = "continue";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .@"continue" },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: keeps item as an identifier" {
    const source = "item";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .identifier = "item" } },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes the structure keyword" {
    const source = "structure";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .structure },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes binding keywords" {
    const source = "val var";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .val },
        .{ .kind = .@"var" },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: tokenizes braces and separators" {
    const source = "{},;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .left_brace },
        .{ .kind = .right_brace },
        .{ .kind = .comma },
        .{ .kind = .semicolon },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: captures integer literal values" {
    const source = "0 1 2 42";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .int_literal = 0 } },
        .{ .kind = .{ .int_literal = 1 } },
        .{ .kind = .{ .int_literal = 2 } },
        .{ .kind = .{ .int_literal = 42 } },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: preserves spaces inside string literals" {
    const source = "\"hello world\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .string_literal = "hello world" } },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: captures string literal content" {
    const source = "\"hello\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .string_literal = "hello" } },
        .{ .kind = .end_of_file },
    });
}

test "Lexer > next: decodes string literal escapes" {
    const source = "\"line\\nquote: \\\" slash: \\\\ tab: \\t\"";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const lexer_pipeline = try setupLexerPipeline(&arena, source);

    const tokens = try collectTokens(lexer_pipeline.lexer);

    try expect(tokens).toMatch(.{
        .{ .kind = .{ .string_literal = "line\nquote: \" slash: \\ tab: \t" } },
        .{ .kind = .end_of_file },
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
        .{ .kind = .{ .string_literal = "first" } },
        .{ .kind = .{ .string_literal = "second" } },
        .{ .kind = .end_of_file },
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
        .{ .kind = .{ .identifier = "answer" } },
        .{ .kind = .end_of_file },
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
        .{ .kind = .{ .identifier = "answer" } },
        .{ .kind = .{ .identifier = "next" } },
        .{ .kind = .end_of_file },
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
        .{ .kind = .{ .identifier = "first" } },
        .{ .kind = .{ .identifier = "second" } },
        .{ .kind = .end_of_file },
    });
}

pub const Lexer = struct {
    pub const next = struct {
        pub const integer_literals = struct {
            test "captures the largest integer literal that fits into an int" {
                const source = "9223372036854775807";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const lexer_pipeline = try setupLexerPipeline(&arena, source);

                const tokens = try collectTokens(lexer_pipeline.lexer);

                try expect(tokens).toMatch(.{
                    .{ .kind = .{ .int_literal = 9223372036854775807 } },
                    .{ .kind = .end_of_file },
                });
            }

            test "emits a diagnostic when an integer literal does not fit into an int" {
                const source = "9223372036854775808";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const lexer_pipeline = try setupLexerPipeline(&arena, source);

                const result = lexer_pipeline.lexer.next();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(lexer_pipeline.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "integer literal is too large for int, the maximum is 9223372036854775807" },
                });
            }
        };
    };
};
