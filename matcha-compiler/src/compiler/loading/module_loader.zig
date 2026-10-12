const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");
const parsing = @import("parsing");
const sources = @import("sources");
const CompileError = diagnostics.CompileError;

/// Loads the root module and every module it reaches through imports, each exactly once.
pub const ModuleLoader = struct {
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,
    parser: *parsing.Parser,

    pub fn init(
        arena: std.mem.Allocator,
        diagnostic_store: *diagnostics.DiagnosticStore,
        source_registry: *sources.SourceRegistry,
        parser: *parsing.Parser,
    ) @This() {
        return .{
            .arena = arena,
            .diagnostic_store = diagnostic_store,
            .source_registry = source_registry,
            .parser = parser,
        };
    }

    /// The root module becomes module 0. The other modules follow in the order the loader discovers them.
    pub fn load(
        self: *@This(),
        root_path: []const u8,
        root_source: []const u8,
    ) !ast.Program {
        var module_id_by_canonical_path = std.StringHashMap(sources.ModuleId).init(self.arena);
        var imported_module_id_by_node_id = ast.ImportedModuleIdByNodeId.init(self.arena);
        var modules = std.ArrayList(ast.Module){};

        const root_module_id = try self.source_registry.add(root_path, root_source);
        std.debug.assert(root_module_id == 0);
        try module_id_by_canonical_path.put(try self.canonicalizePath(root_path), root_module_id);

        // A module is registered when the loader discovers it, before it is parsed, so import cycles end.
        var module_id: sources.ModuleId = 0;
        while (module_id < module_id_by_canonical_path.count()) : (module_id += 1) {
            const source_file = self.source_registry.get(module_id);
            const lexer = lexing.Lexer.init(source_file.source, module_id, self.arena, self.diagnostic_store);
            const module = try self.parser.parse(lexer);
            try modules.append(self.arena, module);

            for (module.statements) |statement| {
                const import_definition = switch (statement.kind) {
                    .item_definition => |item_definition| switch (item_definition.definition) {
                        .import => |import_definition| import_definition,
                        else => continue,
                    },
                    else => continue,
                };
                const imported_module_id = try self.discoverModule(
                    source_file.path,
                    import_definition,
                    &module_id_by_canonical_path,
                );
                try imported_module_id_by_node_id.put(statement.id, imported_module_id);
            }
        }

        return .{
            .modules = try modules.toOwnedSlice(self.arena),
            .imported_module_id_by_node_id = imported_module_id_by_node_id,
        };
    }

    fn discoverModule(
        self: *@This(),
        importing_module_path: []const u8,
        import_definition: ast.ImportDefinition,
        module_id_by_canonical_path: *std.StringHashMap(sources.ModuleId),
    ) CompileError!sources.ModuleId {
        const import_path = import_definition.path_token.kind.string_literal;
        // The import path is relative to the importing module. The joined path stays relative, so diagnostics stay readable.
        const module_path = try std.fs.path.resolve(
            self.arena,
            &.{ std.fs.path.dirname(importing_module_path) orelse "", import_path },
        );

        const canonical_path = self.canonicalizePath(module_path) catch |canonicalize_error| switch (canonicalize_error) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.reportMissingModule(import_definition, import_path),
        };
        if (module_id_by_canonical_path.get(canonical_path)) |module_id| {
            return module_id;
        }

        const module_source = std.fs.cwd().readFileAlloc(
            self.arena,
            module_path,
            std.math.maxInt(usize),
        ) catch |read_error| switch (read_error) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.reportMissingModule(import_definition, import_path),
        };
        const module_id = try self.source_registry.add(module_path, module_source);
        try module_id_by_canonical_path.put(canonical_path, module_id);

        return module_id;
    }

    /// Two paths that reach the same file, for example `a.mt` and `./a.mt`, get the same canonical path.
    fn canonicalizePath(self: *@This(), path: []const u8) ![]const u8 {
        return std.fs.cwd().realpathAlloc(self.arena, path);
    }

    fn reportMissingModule(
        self: *@This(),
        import_definition: ast.ImportDefinition,
        import_path: []const u8,
    ) CompileError {
        try self.diagnostic_store.emitFormattedErrorFromToken(
            self.arena,
            import_definition.path_token,
            "cannot find module '{s}'",
            .{import_path},
        );

        return error.DiagnosticsEmitted;
    }
};
