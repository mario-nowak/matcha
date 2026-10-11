const std = @import("std");
const testing = @import("testing");
const expect = testing.expect;

pub const setupProgramFixture = struct {
    test "parses each source file into its own module with its own module id" {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        const fixture = try testing.setupProgramFixture(&arena, &.{
            .{ .path = "main.mt", .source = "val first = 1;" },
            .{ .path = "other.mt", .source = "val second = 2;" },
        });

        try expect(fixture.program.modules).toMatch(.{
            .{ .statements = .{.{ .kind = .{ .binding_declaration = .{
                .name = .{ .module_id = 0, .kind = .{ .identifier = "first" } },
            } } }} },
            .{ .statements = .{.{ .kind = .{ .binding_declaration = .{
                .name = .{ .module_id = 1, .kind = .{ .identifier = "second" } },
            } } }} },
        });
        try expect(fixture.source_registry.get(1)).toMatch(.{ .path = "other.mt" });
    }
};
