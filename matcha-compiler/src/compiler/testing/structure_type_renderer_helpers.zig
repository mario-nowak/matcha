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
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !StructureTypeRendererFixture {
    const lowering_analyzer_fixture = try setupLoweringAnalyzerFixture(arena, source);
    const lowered_program = lowering_analyzer_fixture.lowering_analyzer.lowerProgram(lowering_analyzer_fixture.analyzed_program);

    const structure_type_renderer = try arena.allocator().create(StructureTypeRenderer);
    structure_type_renderer.* = StructureTypeRenderer.init(arena.allocator());

    return .{
        .lowered_program = lowered_program,
        .structure_type_renderer = structure_type_renderer,
    };
}
