const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");
const parsing = @import("parsing");
const sources = @import("sources");

const ProgramFixture = struct {
    program: ast.Program,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,
};

/// Builds a `Program` with one module per source file. Each source file gets the next `ModuleId`, in the given order.
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

    return .{
        .program = .{
            .modules = modules,
            .imported_module_id_by_node_id = ast.ImportedModuleIdByNodeId.init(arena),
        },
        .diagnostic_store = diagnostic_store,
        .source_registry = source_registry,
    };
}
