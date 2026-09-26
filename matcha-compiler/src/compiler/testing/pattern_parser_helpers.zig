const std = @import("std");
const ast = @import("ast");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const setupLexerPipeline = @import("lexer_helpers.zig").setupLexerPipeline;

const PatternParserFixture = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    pattern_parser: *parsing.PatternParser,
};

pub fn setupPatternParserFixture(arena: *std.heap.ArenaAllocator, source: []const u8) !PatternParserFixture {
    const allocator = arena.allocator();
    const lexer_pipeline = try setupLexerPipeline(arena, source);

    const next_node_id = try allocator.create(ast.NodeId);
    next_node_id.* = 0;

    const pattern_parser = try allocator.create(parsing.PatternParser);
    pattern_parser.* = parsing.PatternParser.init(lexer_pipeline.lexer, allocator, lexer_pipeline.diagnostic_store, next_node_id);

    return .{
        .diagnostic_store = lexer_pipeline.diagnostic_store,
        .pattern_parser = pattern_parser,
    };
}
