const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const ExitBehaviorAnalyzer = @import("semantic_analysis").control_flow_validation.ExitBehaviorAnalyzer;
const setupProgramFixture = @import("program_helpers.zig").setupProgramFixture;

const ExitBehaviorAnalyzerFixture = struct {
    program: ast.Program,
    analyzer: *ExitBehaviorAnalyzer,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupExitBehaviorAnalyzerFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !ExitBehaviorAnalyzerFixture {
    const arena = arena_state.allocator();
    const program_fixture = try setupProgramFixture(arena_state, &.{.{ .path = "main.mt", .source = source }});
    const analyzer = try arena.create(ExitBehaviorAnalyzer);
    analyzer.* = ExitBehaviorAnalyzer.init(arena, program_fixture.diagnostic_store);

    return .{
        .program = program_fixture.program,
        .analyzer = analyzer,
        .diagnostic_store = program_fixture.diagnostic_store,
    };
}
