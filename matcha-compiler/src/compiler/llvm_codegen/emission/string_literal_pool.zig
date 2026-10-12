const std = @import("std");
const ast = @import("ast");
const sources = @import("sources");

pub const StringLiteralGlobal = struct {
    name: []const u8,
    content: []const u8,
    len: usize,
};

pub const StringLiteralPool = struct {
    arena: std.mem.Allocator,
    string_literal_globals: std.ArrayList(StringLiteralGlobal),
    string_literal_global_name_by_node_id: std.AutoHashMap(ast.NodeId, []const u8),
    source_path_global_by_module_id: std.AutoHashMap(sources.ModuleId, StringLiteralGlobal),
    string_literal_global_counter: usize,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
            .string_literal_globals = .{},
            .string_literal_global_name_by_node_id = std.AutoHashMap(ast.NodeId, []const u8).init(arena),
            .source_path_global_by_module_id = std.AutoHashMap(sources.ModuleId, StringLiteralGlobal).init(arena),
            .string_literal_global_counter = 0,
        };
    }

    pub fn reset(self: *@This()) void {
        self.string_literal_globals.clearRetainingCapacity();
        self.string_literal_global_name_by_node_id.clearRetainingCapacity();
        self.source_path_global_by_module_id.clearRetainingCapacity();
        self.string_literal_global_counter = 0;
    }

    pub fn registerLiteral(
        self: *@This(),
        node_id: ast.NodeId,
        content: []const u8,
    ) !StringLiteralGlobal {
        if (self.string_literal_global_name_by_node_id.get(node_id)) |existing_global_name| {
            return .{
                .name = existing_global_name,
                .content = content,
                .len = content.len,
            };
        }

        const string_literal_global = StringLiteralGlobal{
            .name = try self.generateStringLiteralGlobalName(),
            .content = content,
            .len = content.len,
        };
        try self.string_literal_globals.append(self.arena, string_literal_global);
        try self.string_literal_global_name_by_node_id.put(node_id, string_literal_global.name);

        return string_literal_global;
    }

    /// Runtime panics name the file of the failing code. Each module's path becomes one global, shared by all its panics.
    pub fn registerSourcePath(
        self: *@This(),
        module_id: sources.ModuleId,
        path: []const u8,
    ) !StringLiteralGlobal {
        if (self.source_path_global_by_module_id.get(module_id)) |existing_global| {
            return existing_global;
        }

        const source_path_global = StringLiteralGlobal{
            .name = try self.generateStringLiteralGlobalName(),
            .content = path,
            .len = path.len,
        };
        try self.string_literal_globals.append(self.arena, source_path_global);
        try self.source_path_global_by_module_id.put(module_id, source_path_global);

        return source_path_global;
    }

    pub fn globals(self: *const @This()) []const StringLiteralGlobal {
        return self.string_literal_globals.items;
    }

    fn generateStringLiteralGlobalName(self: *@This()) ![]const u8 {
        const global_name = try std.fmt.allocPrint(
            self.arena,
            "@matcha.string_literal.{d}",
            .{self.string_literal_global_counter},
        );
        self.string_literal_global_counter += 1;

        return global_name;
    }
};
