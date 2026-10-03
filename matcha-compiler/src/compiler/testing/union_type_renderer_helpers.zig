const std = @import("std");
const llvm_codegen = @import("llvm_codegen");

const LoweredProgram = llvm_codegen.lowering.LoweredProgram;
const UnionTypeRenderer = llvm_codegen.rendering.UnionTypeRenderer;
const setupLoweringAnalyzerFixture = @import("lowering_analyzer_helpers.zig").setupLoweringAnalyzerFixture;

const UnionTypeRendererFixture = struct {
    lowered_program: LoweredProgram,
    union_type_renderer: *UnionTypeRenderer,
};

pub fn setupUnionTypeRendererFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !UnionTypeRendererFixture {
    const lowering_analyzer_fixture = try setupLoweringAnalyzerFixture(arena, source);
    const lowered_program = try lowering_analyzer_fixture.lowering_analyzer.lowerProgram(lowering_analyzer_fixture.analyzed_program);

    const union_type_renderer = try arena.allocator().create(UnionTypeRenderer);
    union_type_renderer.* = UnionTypeRenderer.init(arena.allocator());

    return .{
        .lowered_program = lowered_program,
        .union_type_renderer = union_type_renderer,
    };
}
