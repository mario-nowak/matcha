const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const sources = @import("sources");
const NameResolver = @import("semantic_analysis").name_resolution.NameResolver;
const setupProgramFixture = @import("program_helpers.zig").setupProgramFixture;

const NameResolverFixture = struct {
    program: ast.Program,
    resolver: *NameResolver,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,
};

pub fn setupNameResolverFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !NameResolverFixture {
    return setupNameResolverFixtureFromSourceFiles(arena_state, &.{.{ .path = "main.mt", .source = source }});
}

pub fn setupNameResolverFixtureFromSourceFiles(
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !NameResolverFixture {
    const arena = arena_state.allocator();
    const program_fixture = try setupProgramFixture(arena_state, source_files);
    const resolver = try arena.create(NameResolver);
    resolver.* = NameResolver.init(arena, program_fixture.diagnostic_store);

    return .{
        .program = program_fixture.program,
        .resolver = resolver,
        .diagnostic_store = program_fixture.diagnostic_store,
        .source_registry = program_fixture.source_registry,
    };
}
