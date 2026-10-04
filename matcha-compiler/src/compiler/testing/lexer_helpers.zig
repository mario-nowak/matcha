const std = @import("std");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");

const LexerPipeline = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    lexer: *lexing.Lexer,
};

pub fn setupLexerPipeline(arena_state: *std.heap.ArenaAllocator, source: []const u8) !LexerPipeline {
    const arena = arena_state.allocator();
    const diagnostic_store = try arena.create(diagnostics.DiagnosticStore);
    diagnostic_store.* = diagnostics.DiagnosticStore.init(arena);

    const lexer = try arena.create(lexing.Lexer);
    lexer.* = lexing.Lexer.init(source, arena, diagnostic_store);

    return .{
        .diagnostic_store = diagnostic_store,
        .lexer = lexer,
    };
}

pub fn collectTokens(lexer: *lexing.Lexer) ![]lexing.Token {
    const arena = lexer.arena;
    var tokens = std.ArrayList(lexing.Token){};
    while (true) {
        const token = try lexer.next();
        try tokens.append(arena, token);
        if (token.kind == .EndOfFile) break;
    }
    return tokens.toOwnedSlice(arena);
}
