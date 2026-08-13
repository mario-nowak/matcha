const std = @import("std");
const ast = @import("ast");

pub const StringLiteralGlobal = struct {
    name: []const u8,
    content: []const u8,
    len: usize,
};

pub const StringLiteralPool = struct {
    allocator: std.mem.Allocator,
    string_literal_globals: std.ArrayList(StringLiteralGlobal),
    string_literal_global_name_by_node_id: std.AutoHashMap(ast.NodeId, []const u8),
    string_literal_global_counter: usize,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .string_literal_globals = .{},
            .string_literal_global_name_by_node_id = std.AutoHashMap(ast.NodeId, []const u8).init(allocator),
            .string_literal_global_counter = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.string_literal_globals.deinit(self.allocator);
        self.string_literal_global_name_by_node_id.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.string_literal_globals.clearRetainingCapacity();
        self.string_literal_global_name_by_node_id.clearRetainingCapacity();
        self.string_literal_global_counter = 0;
    }

    pub fn intern(
        self: *@This(),
        node_id: ast.NodeId,
        content: []const u8,
    ) StringLiteralGlobal {
        if (self.string_literal_global_name_by_node_id.get(node_id)) |existing_global_name| {
            return .{
                .name = existing_global_name,
                .content = content,
                .len = content.len,
            };
        }

        const string_literal_global = StringLiteralGlobal{
            .name = self.generateStringLiteralGlobalName(),
            .content = content,
            .len = content.len,
        };
        self.string_literal_globals.append(self.allocator, string_literal_global) catch unreachable;
        self.string_literal_global_name_by_node_id.put(node_id, string_literal_global.name) catch unreachable;

        return string_literal_global;
    }

    pub fn globals(self: *const @This()) []const StringLiteralGlobal {
        return self.string_literal_globals.items;
    }

    fn generateStringLiteralGlobalName(self: *@This()) []const u8 {
        const global_name = std.fmt.allocPrint(
            self.allocator,
            "@.string_literal_{d}",
            .{self.string_literal_global_counter},
        ) catch unreachable;
        self.string_literal_global_counter += 1;

        return global_name;
    }
};
