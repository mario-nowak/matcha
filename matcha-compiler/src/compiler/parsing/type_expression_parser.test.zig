const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const type_expressions = @import("type_expressions");

const ParsedTypeExpression = struct {
    arena: std.heap.ArenaAllocator,
    type_expression: *type_expressions.TypeExpression,

    fn deinit(self: *ParsedTypeExpression) void {
        self.arena.deinit();
    }
};

fn parseTypeExpression(source: []const u8) !ParsedTypeExpression {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, source);

    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.TypeExpressionParser.init(&lexer, allocator, &diagnostic_store);
    const type_expression = try parser.parse();
    return .{
        .arena = arena,
        .type_expression = type_expression,
    };
}

test "type expression parser parses named types" {
    var parsed = try parseTypeExpression("int");
    defer parsed.deinit();

    switch (parsed.type_expression.*) {
        .Named => |named_type_expression| {
            try std.testing.expectEqualStrings("int", named_type_expression.name_token.kind.Identifier);
        },
        else => return error.UnexpectedTypeExpressionKind,
    }
}

test "type expression parser parses array suffixes" {
    var parsed = try parseTypeExpression("string[][]");
    defer parsed.deinit();

    switch (parsed.type_expression.*) {
        .Array => |outer_array| switch (outer_array.element_type.*) {
            .Array => |inner_array| switch (inner_array.element_type.*) {
                .Named => |named_type_expression| {
                    try std.testing.expectEqualStrings("string", named_type_expression.name_token.kind.Identifier);
                },
                else => return error.UnexpectedTypeExpressionKind,
            },
            else => return error.UnexpectedTypeExpressionKind,
        },
        else => return error.UnexpectedTypeExpressionKind,
    }
}

test "type expression parser rejects missing right bracket" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, "int[");
    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.TypeExpressionParser.init(&lexer, allocator, &diagnostic_store);
    try std.testing.expectError(error.DiagnosticsEmitted, parser.parse());
}

test "type expression parser rejects missing base type" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, "[]");
    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.TypeExpressionParser.init(&lexer, allocator, &diagnostic_store);
    try std.testing.expectError(error.DiagnosticsEmitted, parser.parse());
}
