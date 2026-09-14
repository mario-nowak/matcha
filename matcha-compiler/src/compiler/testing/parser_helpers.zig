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

pub fn setupParserPipeline(arena: *std.heap.ArenaAllocator, source: []const u8) !ParserPipeline {
    const allocator = arena.allocator();
    const lexer_pipeline = try setupLexerPipeline(arena, source);

    const parser = try allocator.create(parsing.Parser);
    parser.* = parsing.Parser.init(lexer_pipeline.lexer.*, allocator, lexer_pipeline.diagnostic_store);

    return .{
        .diagnostic_store = lexer_pipeline.diagnostic_store,
        .lexer = lexer_pipeline.lexer,
        .parser = parser,
    };
}
