const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");
const loading = @import("loading");
const parsing = @import("parsing");
const sources = @import("sources");

const ProgramFixture = struct {
    program: ast.Program,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,
};

/// Builds a `Program` with one module per source file. Each source file gets the next `ModuleId`, in the given order.
/// An import must name one of the source files, or the builtins.
pub fn setupProgramFixture(
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !ProgramFixture {
    const arena = arena_state.allocator();
    const diagnostic_store = try arena.create(diagnostics.DiagnosticStore);
    diagnostic_store.* = diagnostics.DiagnosticStore.init(arena);
    const source_registry = try arena.create(sources.SourceRegistry);
    source_registry.* = sources.SourceRegistry.init(arena);
    var parser = parsing.Parser.init(arena, diagnostic_store);

    const modules = try arena.alloc(ast.Module, source_files.len);
    for (source_files, modules) |source_file, *module| {
        const module_id = try source_registry.add(source_file.path, source_file.source);
        const lexer = lexing.Lexer.init(source_file.source, module_id, arena, diagnostic_store);
        module.* = try parser.parse(lexer);
    }

    // Connects each import to the source file at its path, as the module loader does with real files.
    var import_target_by_node_id = ast.ImportTargetByNodeId.init(arena);
    for (source_files, modules) |source_file, module| {
        for (module.statements) |statement| {
            const import_definition = switch (statement.kind) {
                .item_definition => |item_definition| switch (item_definition.definition) {
                    .import => |import_definition| import_definition,
                    else => continue,
                },
                else => continue,
            };
            const import_target: ast.ImportTarget = switch (try loading.resolveImportPath(
                arena,
                source_file.path,
                import_definition.path_token.kind.string_literal,
            )) {
                .builtins => .builtins,
                .module_path => |module_path| .{ .module = for (source_files, 0..) |candidate_source_file, module_id| {
                    if (std.mem.eql(u8, candidate_source_file.path, module_path)) break @intCast(module_id);
                } else return error.ImportedSourceFileMissing },
                .missing_extension => return error.ImportPathMissingExtension,
            };
            try import_target_by_node_id.put(statement.id, import_target);
        }
    }

    return .{
        .program = .{
            .modules = modules,
            .import_target_by_node_id = import_target_by_node_id,
        },
        .diagnostic_store = diagnostic_store,
        .source_registry = source_registry,
    };
}
