const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const ExitBehaviorAnalyzer = @import("semantic_analysis").control_flow_validation.ExitBehaviorAnalyzer;
const setupParserPipeline = @import("parser_helpers.zig").setupParserPipeline;

const ExitBehaviorAnalyzerFixture = struct {
    program: ast.Module,
    analyzer: *ExitBehaviorAnalyzer,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupExitBehaviorAnalyzerFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !ExitBehaviorAnalyzerFixture {
    const arena = arena_state.allocator();
    const parser_pipeline = try setupParserPipeline(arena_state, source);
    const program = try parser_pipeline.parser.parse();
    const analyzer = try arena.create(ExitBehaviorAnalyzer);
    analyzer.* = ExitBehaviorAnalyzer.init(arena, parser_pipeline.diagnostic_store);

    return .{
        .program = program,
        .analyzer = analyzer,
        .diagnostic_store = parser_pipeline.diagnostic_store,
    };
}
