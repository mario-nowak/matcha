const std = @import("std");

pub const UnionTypeRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
        };
    }

    fn renderUnionTypeDefinition(_: *@This()) []const u8 {}
};
