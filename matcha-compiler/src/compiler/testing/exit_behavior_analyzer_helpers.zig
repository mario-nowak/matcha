const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const ExitBehaviorAnalyzer = @import("semantic_analysis").control_flow_validation.ExitBehaviorAnalyzer;
const setupParserPipeline = @import("parser_helpers.zig").setupParserPipeline;

const ExitBehaviorAnalyzerFixture = struct {
    program: ast.Program,
    analyzer: *ExitBehaviorAnalyzer,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupExitBehaviorAnalyzerFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !ExitBehaviorAnalyzerFixture {
    const allocator = arena.allocator();
    const parser_pipeline = try setupParserPipeline(arena, source);
    const program = try parser_pipeline.parser.parse();
    const analyzer = try allocator.create(ExitBehaviorAnalyzer);
    analyzer.* = ExitBehaviorAnalyzer.init(allocator, parser_pipeline.diagnostic_store);

    return .{
        .program = program,
        .analyzer = analyzer,
        .diagnostic_store = parser_pipeline.diagnostic_store,
    };
}
