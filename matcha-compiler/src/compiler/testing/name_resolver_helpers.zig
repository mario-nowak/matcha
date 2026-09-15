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
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !NameResolverFixture {
    const allocator = arena.allocator();
    const parser_pipeline = try setupParserPipeline(arena, source);
    const program = try parser_pipeline.parser.parse();
    const resolver = try allocator.create(NameResolver);
    resolver.* = NameResolver.init(allocator, parser_pipeline.diagnostic_store);

    return .{
        .program = program,
        .resolver = resolver,
        .diagnostic_store = parser_pipeline.diagnostic_store,
    };
}
