const std = @import("std");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");

const LexerPipeline = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    lexer: *lexing.Lexer,
};

pub fn setupLexerPipeline(arena: *std.heap.ArenaAllocator, source: []const u8) !LexerPipeline {
    const allocator = arena.allocator();
    const diagnostic_store = try allocator.create(diagnostics.DiagnosticStore);
    diagnostic_store.* = diagnostics.DiagnosticStore.init(allocator);

    const lexer = try allocator.create(lexing.Lexer);
    lexer.* = lexing.Lexer.init(source, allocator, diagnostic_store);

    return .{
        .diagnostic_store = diagnostic_store,
        .lexer = lexer,
    };
}

pub fn collectTokens(lexer: *lexing.Lexer) ![]lexing.Token {
    const allocator = lexer.allocator;
    var tokens = std.ArrayList(lexing.Token){};
    defer tokens.deinit(allocator);
    while (true) {
        const token = try lexer.next();
        try tokens.append(allocator, token);
        if (token.kind == .EndOfFile) break;
    }
    return tokens.toOwnedSlice(allocator);
}
