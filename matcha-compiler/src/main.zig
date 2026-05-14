const std = @import("std");

const cli = @import("cli");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var command_line_arguments = try std.process.ArgIterator.initWithAllocator(allocator);
    defer command_line_arguments.deinit();
    _ = command_line_arguments.skip();

    const exit_code = cli.run(allocator, &command_line_arguments) catch {
        std.process.exit(1);
    };
    std.process.exit(exit_code);
}
