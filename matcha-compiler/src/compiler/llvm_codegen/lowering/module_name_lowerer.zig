const std = @import("std");
const sources = @import("sources");

/// Turns a module into the prefix of its LLVM names, for example `matcha.directory.lib.module.util` for `lib/util.mt`.
/// The path is relative to the directory of the root module, the first registered module, so the names don't depend on where the project lives.
pub const ModuleNameLowerer = struct {
    arena: std.mem.Allocator,
    source_registry: *const sources.SourceRegistry,

    pub fn init(arena: std.mem.Allocator, source_registry: *const sources.SourceRegistry) @This() {
        return .{
            .arena = arena,
            .source_registry = source_registry,
        };
    }

    pub fn lower(self: *const @This(), module_id: sources.ModuleId) ![]const u8 {
        const root_directory = std.fs.path.dirname(self.source_registry.get(0).path) orelse "";
        const relative_path = try std.fs.path.relative(self.arena, root_directory, self.source_registry.get(module_id).path);

        var name = std.ArrayList(u8){};
        try name.appendSlice(self.arena, "matcha");
        var segments = std.mem.splitScalar(u8, relative_path, std.fs.path.sep);
        while (segments.next()) |segment| {
            if (segments.peek() == null) {
                try name.appendSlice(self.arena, ".module.");
                try self.appendEscaped(&name, std.fs.path.stem(segment));
            } else {
                try name.appendSlice(self.arena, ".directory.");
                try self.appendEscaped(&name, segment);
            }
        }
        return name.toOwnedSlice(self.arena);
    }

    /// Keeps letters, digits, `_` and `-`, and writes every other byte as `$` plus two hex digits.
    /// No name segment then contains a `.`, and two different paths never produce the same name.
    fn appendEscaped(self: *const @This(), name: *std.ArrayList(u8), segment: []const u8) !void {
        for (segment) |byte| {
            switch (byte) {
                'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => try name.append(self.arena, byte),
                else => try name.print(self.arena, "${X:0>2}", .{byte}),
            }
        }
    }
};
