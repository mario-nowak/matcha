const std = @import("std");
const semantic_analysis = @import("semantic_analysis");

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const setupAnalyzedProgram = @import("analyzed_program_helpers.zig").setupAnalyzedProgram;

pub fn LowererFixture(comptime Lowerer: type) type {
    return struct {
        analyzed_program: *const AnalyzedProgram,
        lowerer: *Lowerer,
    };
}

/// The lowerers only differ in the table they produce, so one fixture serves all of them.
pub fn setupLowererFixture(
    comptime Lowerer: type,
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !LowererFixture(Lowerer) {
    const analyzed_program = try setupAnalyzedProgram(arena, source);

    const lowerer = try arena.allocator().create(Lowerer);
    lowerer.* = Lowerer.init(arena.allocator());

    return .{
        .analyzed_program = analyzed_program,
        .lowerer = lowerer,
    };
}
