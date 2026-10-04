const std = @import("std");
const string_literal_pool_module = @import("emission");

const StringLiteralPool = string_literal_pool_module.StringLiteralPool;

pub const StringLiteralRenderer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{ .arena = arena };
    }

    pub fn renderGlobals(self: *@This(), string_literal_pool: *const StringLiteralPool) []const u8 {
        var globals_buffer = std.ArrayList(u8){};

        for (string_literal_pool.globals(), 0..) |string_literal_global, index| {
            const rendered_content = self.renderLlvmStringLiteralContent(string_literal_global.content);
            globals_buffer.writer(self.arena).print(
                "{s} = private unnamed_addr constant [{d} x i8] c\"{s}\"",
                .{ string_literal_global.name, string_literal_global.len, rendered_content },
            ) catch unreachable;
            if (index + 1 < string_literal_pool.globals().len) {
                globals_buffer.writer(self.arena).print("\n", .{}) catch unreachable;
            }
        }

        return std.fmt.allocPrint(self.arena, "{s}", .{globals_buffer.items}) catch unreachable;
    }

    fn renderLlvmStringLiteralContent(self: *@This(), content: []const u8) []const u8 {
        var rendered_content_buffer = std.ArrayList(u8){};

        for (content) |byte| {
            if (byte >= 0x20 and byte <= 0x7e and byte != '\\' and byte != '"') {
                rendered_content_buffer.append(self.arena, byte) catch unreachable;
                continue;
            }

            rendered_content_buffer.writer(self.arena).print("\\{X:0>2}", .{byte}) catch unreachable;
        }

        return std.fmt.allocPrint(self.arena, "{s}", .{rendered_content_buffer.items}) catch unreachable;
    }
};
