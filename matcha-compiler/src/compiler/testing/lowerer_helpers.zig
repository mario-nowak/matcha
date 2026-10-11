const std = @import("std");
const sources = @import("sources");
const semantic_analysis = @import("semantic_analysis");
const lowering = @import("llvm_codegen").lowering;

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const setupAnalyzedProgramFixture = @import("analyzed_program_helpers.zig").setupAnalyzedProgramFixture;

pub fn LowererFixture(comptime Lowerer: type) type {
    return struct {
        analyzed_program: *const AnalyzedProgram,
        lowerer: *Lowerer,
    };
}

/// The lowerers only differ in the table they produce, so one fixture serves all of them.
pub fn setupLowererFixture(
    comptime Lowerer: type,
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !LowererFixture(Lowerer) {
    return setupLowererFixtureFromSourceFiles(Lowerer, arena_state, &.{.{ .path = "main.mt", .source = source }});
}

pub fn setupLowererFixtureFromSourceFiles(
    comptime Lowerer: type,
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !LowererFixture(Lowerer) {
    const arena = arena_state.allocator();
    const analyzed_program_fixture = try setupAnalyzedProgramFixture(arena_state, source_files);

    const lowerer = try arena.create(Lowerer);
    // Only the lowerers that name LLVM symbols depend on the module names.
    if (@hasField(Lowerer, "module_name_lowerer")) {
        const module_name_lowerer = try arena.create(lowering.ModuleNameLowerer);
        module_name_lowerer.* = lowering.ModuleNameLowerer.init(arena, analyzed_program_fixture.source_registry);
        lowerer.* = Lowerer.init(arena, module_name_lowerer);
    } else {
        lowerer.* = Lowerer.init(arena);
    }

    return .{
        .analyzed_program = analyzed_program_fixture.analyzed_program,
        .lowerer = lowerer,
    };
}
