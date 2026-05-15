const std = @import("std");
const Command = @import("command.zig").Command;
const parser = @import("parser.zig");

test "parse bare invocation as help" {
    const command_line = "matcha";

    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, command_line);
    defer iter.deinit();
    _ = iter.next();

    const command = try parser.parse(std.testing.allocator, &iter);
    try std.testing.expectEqualDeep(Command{ .help = null }, command);
}

test "parse build command with output" {
    const command_line = "matcha build examples/learning-matcha.mt --output zig-out/bin/learning-matcha";

    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, command_line);
    defer iter.deinit();
    _ = iter.next();

    const command = try parser.parse(std.testing.allocator, &iter);
    switch (command) {
        .build => |build| {
            try std.testing.expectEqualStrings("examples/learning-matcha.mt", build.input_path);
            try std.testing.expectEqualStrings("zig-out/bin/learning-matcha", build.output_path.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parse run command" {
    const command_line = "matcha run examples/aoc-2024-01.mt";

    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, command_line);
    defer iter.deinit();
    _ = iter.next();

    const command = try parser.parse(std.testing.allocator, &iter);
    switch (command) {
        .run => |run| {
            try std.testing.expectEqualStrings("examples/aoc-2024-01.mt", run.input_path);
            try std.testing.expectEqual(@as(usize, 0), run.program_arguments.len);
        },
        else => try std.testing.expect(false),
    }
}

test "parse run command with forwarded program arguments" {
    const command_line = "matcha run examples/aoc-2024-01.mt -- examples/data/aoc-2024-01-input.txt --verbose";

    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, command_line);
    defer iter.deinit();
    _ = iter.next();

    const command = try parser.parse(std.testing.allocator, &iter);
    switch (command) {
        .run => |run| {
            try std.testing.expectEqualStrings("examples/aoc-2024-01.mt", run.input_path);
            try std.testing.expectEqual(@as(usize, 2), run.program_arguments.len);
            try std.testing.expectEqualStrings("examples/data/aoc-2024-01-input.txt", run.program_arguments[0]);
            try std.testing.expectEqualStrings("--verbose", run.program_arguments[1]);
        },
        else => try std.testing.expect(false),
    }
}
