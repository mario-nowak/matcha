const std = @import("std");
const llvm_codegen = @import("llvm_codegen");

const LoweredProgram = llvm_codegen.lowering.LoweredProgram;
const StructureTypeRenderer = llvm_codegen.rendering.StructureTypeRenderer;
const setupLoweringAnalyzerFixture = @import("lowering_analyzer_helpers.zig").setupLoweringAnalyzerFixture;

const StructureTypeRendererFixture = struct {
    lowered_program: LoweredProgram,
    structure_type_renderer: *StructureTypeRenderer,
};

pub fn setupStructureTypeRendererFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !StructureTypeRendererFixture {
    const lowering_analyzer_fixture = try setupLoweringAnalyzerFixture(arena_state, source);
    const lowered_program = try lowering_analyzer_fixture.lowering_analyzer.lowerProgram(lowering_analyzer_fixture.analyzed_program);

    const structure_type_renderer = try arena_state.allocator().create(StructureTypeRenderer);
    structure_type_renderer.* = StructureTypeRenderer.init(arena_state.allocator());

    return .{
        .lowered_program = lowered_program,
        .structure_type_renderer = structure_type_renderer,
    };
}
