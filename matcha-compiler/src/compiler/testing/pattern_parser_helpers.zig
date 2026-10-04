const std = @import("std");
const ast = @import("ast");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const setupLexerPipeline = @import("lexer_helpers.zig").setupLexerPipeline;

const PatternParserFixture = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    pattern_parser: *parsing.PatternParser,
};

pub fn setupPatternParserFixture(arena_state: *std.heap.ArenaAllocator, source: []const u8) !PatternParserFixture {
    const arena = arena_state.allocator();
    const lexer_pipeline = try setupLexerPipeline(arena_state, source);

    const next_node_id = try arena.create(ast.NodeId);
    next_node_id.* = 0;

    const pattern_parser = try arena.create(parsing.PatternParser);
    pattern_parser.* = parsing.PatternParser.init(lexer_pipeline.lexer, arena, lexer_pipeline.diagnostic_store, next_node_id);

    return .{
        .diagnostic_store = lexer_pipeline.diagnostic_store,
        .pattern_parser = pattern_parser,
    };
}
