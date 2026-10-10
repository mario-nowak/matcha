const std = @import("std");

/// Identifies one module, that is one source file, of a compilation.
pub const ModuleId = u32;

pub const SourceFile = struct {
    path: []const u8,
    source: []const u8,
};

/// Keeps the path and source of every module, so a diagnostic can show the file it belongs to.
pub const SourceRegistry = struct {
    arena: std.mem.Allocator,
    source_files: std.ArrayList(SourceFile),

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
            .source_files = .{},
        };
    }

    pub fn add(self: *@This(), path: []const u8, source: []const u8) !ModuleId {
        const module_id: ModuleId = @intCast(self.source_files.items.len);
        try self.source_files.append(self.arena, .{ .path = path, .source = source });
        return module_id;
    }

    pub fn get(self: *const @This(), module_id: ModuleId) SourceFile {
        return self.source_files.items[module_id];
    }
};
