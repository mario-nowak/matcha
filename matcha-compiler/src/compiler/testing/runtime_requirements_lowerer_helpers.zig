const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const RuntimeRequirementsLowerer = llvm_codegen.lowering.RuntimeRequirementsLowerer;
const setupAnalyzedProgram = @import("analyzed_program_helpers.zig").setupAnalyzedProgram;

const RuntimeRequirementsLowererFixture = struct {
    analyzed_program: *const AnalyzedProgram,
    runtime_requirements_lowerer: *RuntimeRequirementsLowerer,
};

pub fn setupRuntimeRequirementsLowererFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !RuntimeRequirementsLowererFixture {
    const analyzed_program = try setupAnalyzedProgram(arena, source);

    const runtime_requirements_lowerer = try arena.allocator().create(RuntimeRequirementsLowerer);
    runtime_requirements_lowerer.* = RuntimeRequirementsLowerer.init();

    return .{
        .analyzed_program = analyzed_program,
        .runtime_requirements_lowerer = runtime_requirements_lowerer,
    };
}
