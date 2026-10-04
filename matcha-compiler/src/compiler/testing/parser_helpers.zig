const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const setupLexerPipeline = @import("lexer_helpers.zig").setupLexerPipeline;

const ParserPipeline = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    lexer: *lexing.Lexer,
    parser: *parsing.Parser,
};

pub fn setupParserPipeline(arena_state: *std.heap.ArenaAllocator, source: []const u8) !ParserPipeline {
    const arena = arena_state.allocator();
    const lexer_pipeline = try setupLexerPipeline(arena_state, source);

    const parser = try arena.create(parsing.Parser);
    parser.* = parsing.Parser.init(lexer_pipeline.lexer.*, arena, lexer_pipeline.diagnostic_store);

    return .{
        .diagnostic_store = lexer_pipeline.diagnostic_store,
        .lexer = lexer_pipeline.lexer,
        .parser = parser,
    };
}
