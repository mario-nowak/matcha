const std = @import("std");

const cli = @import("cli");

pub fn main() !void {
    // The compiler never frees: everything it allocates lives until the process exits.
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var command_line_arguments = try std.process.ArgIterator.initWithAllocator(arena);
    _ = command_line_arguments.skip();

    const exit_code = cli.run(arena, &command_line_arguments) catch |run_error| {
        cli.reportUnreportedError(run_error);
        std.process.exit(1);
    };
    std.process.exit(exit_code);
}
