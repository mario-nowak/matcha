const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const NameResolver = @import("semantic_analysis").name_resolution.NameResolver;
const setupParserPipeline = @import("parser_helpers.zig").setupParserPipeline;

const NameResolverFixture = struct {
    program: ast.Program,
    resolver: *NameResolver,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupNameResolverFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !NameResolverFixture {
    const arena = arena_state.allocator();
    const parser_pipeline = try setupParserPipeline(arena_state, source);
    const module = try parser_pipeline.parser.parse();
    const program = ast.Program{ .modules = try arena.dupe(ast.Module, &.{module}) };
    const resolver = try arena.create(NameResolver);
    resolver.* = NameResolver.init(arena, parser_pipeline.diagnostic_store);

    return .{
        .program = program,
        .resolver = resolver,
        .diagnostic_store = parser_pipeline.diagnostic_store,
    };
}
