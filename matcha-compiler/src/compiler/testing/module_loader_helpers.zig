const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const loading = @import("loading");
const parsing = @import("parsing");
const sources = @import("sources");

const ModuleLoaderFixture = struct {
    arena: std.mem.Allocator,
    directory: *std.testing.TmpDir,
    module_loader: *loading.ModuleLoader,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,

    /// The path of a file in the temporary directory, relative to the working directory like a path from the command line.
    pub fn pathOf(self: *const @This(), sub_path: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ ".zig-cache", "tmp", &self.directory.sub_path, sub_path });
    }

    /// Reads the root module from the temporary directory, as the pipeline does, and loads the program.
    pub fn load(self: *const @This(), root_sub_path: []const u8) !ast.Program {
        const root_source = try self.directory.dir.readFileAlloc(self.arena, root_sub_path, std.math.maxInt(usize));
        return self.module_loader.load(try self.pathOf(root_sub_path), root_source);
    }
};

pub fn setupModuleLoaderFixture(arena_state: *std.heap.ArenaAllocator, directory: *std.testing.TmpDir) !ModuleLoaderFixture {
    const arena = arena_state.allocator();
    const diagnostic_store = try arena.create(diagnostics.DiagnosticStore);
    diagnostic_store.* = diagnostics.DiagnosticStore.init(arena);
    const source_registry = try arena.create(sources.SourceRegistry);
    source_registry.* = sources.SourceRegistry.init(arena);
    const parser = try arena.create(parsing.Parser);
    parser.* = parsing.Parser.init(arena, diagnostic_store);
    const module_loader = try arena.create(loading.ModuleLoader);
    module_loader.* = loading.ModuleLoader.init(arena, diagnostic_store, source_registry, parser);

    return .{
        .arena = arena,
        .directory = directory,
        .module_loader = module_loader,
        .diagnostic_store = diagnostic_store,
        .source_registry = source_registry,
    };
}
