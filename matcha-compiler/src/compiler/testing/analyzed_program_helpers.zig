const std = @import("std");
const semantic_analysis = @import("semantic_analysis");

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const setupRuntimeRepresentationAnalyzerFixture = @import("runtime_representation_analyzer_helpers.zig").setupRuntimeRepresentationAnalyzerFixture;

/// Runs the full semantic analysis. Lowering results keep a pointer to the analyzed program, so it lives in the arena.
pub fn setupAnalyzedProgram(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !*const AnalyzedProgram {
    const runtime_representation_analyzer_fixture = try setupRuntimeRepresentationAnalyzerFixture(arena, source);
    const runtime_representation_result = try runtime_representation_analyzer_fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(
        &runtime_representation_analyzer_fixture.type_check_result,
    );

    const analyzed_program = try arena.allocator().create(AnalyzedProgram);
    analyzed_program.* = AnalyzedProgram.init(
        runtime_representation_analyzer_fixture.resolved_program,
        runtime_representation_analyzer_fixture.exit_behavior_by_node_id,
        runtime_representation_analyzer_fixture.type_check_result,
        runtime_representation_result,
    );

    return analyzed_program;
}
