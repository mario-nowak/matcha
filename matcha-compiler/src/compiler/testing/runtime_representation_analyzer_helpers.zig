const std = @import("std");
const symbols = @import("symbols");
const semantic_analysis = @import("semantic_analysis");

const TypeCheckResult = semantic_analysis.type_checking.TypeCheckResult;
const RuntimeRepresentationAnalyzer = semantic_analysis.runtime_representation.RuntimeRepresentationAnalyzer;
const setupNodeTypeAnalyzerFixture = @import("node_type_analyzer_helpers.zig").setupNodeTypeAnalyzerFixture;

const RuntimeRepresentationAnalyzerFixture = struct {
    resolved_program: symbols.ResolvedProgram,
    type_check_result: TypeCheckResult,
    runtime_representation_analyzer: *RuntimeRepresentationAnalyzer,
};

pub fn setupRuntimeRepresentationAnalyzerFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !RuntimeRepresentationAnalyzerFixture {
    const node_type_analyzer_fixture = try setupNodeTypeAnalyzerFixture(arena, source);
    const type_check_result = try node_type_analyzer_fixture.node_type_analyzer.analyzeProgram(
        &node_type_analyzer_fixture.resolved_program,
        node_type_analyzer_fixture.exit_behavior_by_node_id,
    );

    const runtime_representation_analyzer = try arena.allocator().create(RuntimeRepresentationAnalyzer);
    runtime_representation_analyzer.* = RuntimeRepresentationAnalyzer.init(arena.allocator());

    return .{
        .resolved_program = node_type_analyzer_fixture.resolved_program,
        .type_check_result = type_check_result,
        .runtime_representation_analyzer = runtime_representation_analyzer,
    };
}
