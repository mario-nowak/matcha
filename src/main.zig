const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const commandLineArguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, commandLineArguments);
    const fileName = commandLineArguments[1];

    const cwd = std.fs.cwd();
    const fileContents = try cwd.readFileAlloc(allocator, fileName, 4096);
    defer allocator.free(fileContents);

    // Print file contents
    std.debug.print("{s}", .{fileContents});
}
