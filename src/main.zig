const std = @import("std");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

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

    var lexerTest = lexer.Lexer.init(fileContents, allocator);
    defer lexerTest.deinit();

    var parserTest = parser.Parser.init(lexerTest, allocator);
    const expression = try parserTest.parse(.{ .currentBindingPower = 0 });
    std.debug.print("Expression: {f}\n", .{expression});

    // Print file contents
    std.debug.print("{s}\n", .{fileContents});
}
