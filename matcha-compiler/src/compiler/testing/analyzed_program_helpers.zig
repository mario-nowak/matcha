const std = @import("std");
const sources = @import("sources");
const semantic_analysis = @import("semantic_analysis");

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const setupRuntimeRepresentationAnalyzerFixtureFromSourceFiles = @import("runtime_representation_analyzer_helpers.zig").setupRuntimeRepresentationAnalyzerFixtureFromSourceFiles;

const AnalyzedProgramFixture = struct {
    analyzed_program: *const AnalyzedProgram,
    source_registry: *sources.SourceRegistry,
};

/// Runs the full semantic analysis. Lowering results keep a pointer to the analyzed program, so it lives in the arena_state.
pub fn setupAnalyzedProgramFixture(
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !AnalyzedProgramFixture {
    const runtime_representation_analyzer_fixture = try setupRuntimeRepresentationAnalyzerFixtureFromSourceFiles(arena_state, source_files);
    const runtime_representation_result = try runtime_representation_analyzer_fixture.runtime_representation_analyzer.analyzeRuntimeRepresentations(
        &runtime_representation_analyzer_fixture.type_check_result,
    );

    const analyzed_program = try arena_state.allocator().create(AnalyzedProgram);
    analyzed_program.* = AnalyzedProgram.init(
        runtime_representation_analyzer_fixture.resolved_program,
        runtime_representation_analyzer_fixture.exit_behavior_by_node_id,
        runtime_representation_analyzer_fixture.type_check_result,
        runtime_representation_result,
    );

    return .{
        .analyzed_program = analyzed_program,
        .source_registry = runtime_representation_analyzer_fixture.source_registry,
    };
}
