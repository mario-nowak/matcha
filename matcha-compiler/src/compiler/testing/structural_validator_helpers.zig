const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const sources = @import("sources");
const StructuralValidator = @import("semantic_analysis").control_flow_validation.StructuralValidator;
const setupProgramFixture = @import("program_helpers.zig").setupProgramFixture;

const StructuralValidatorFixture = struct {
    program: ast.Program,
    validator: *StructuralValidator,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupStructuralValidatorFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !StructuralValidatorFixture {
    return setupStructuralValidatorFixtureFromSourceFiles(arena_state, &.{.{ .path = "main.mt", .source = source }});
}

pub fn setupStructuralValidatorFixtureFromSourceFiles(
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !StructuralValidatorFixture {
    const arena = arena_state.allocator();
    const program_fixture = try setupProgramFixture(arena_state, source_files);
    const validator = try arena.create(StructuralValidator);
    validator.* = StructuralValidator.init(program_fixture.diagnostic_store);

    return .{
        .program = program_fixture.program,
        .validator = validator,
        .diagnostic_store = program_fixture.diagnostic_store,
    };
}
