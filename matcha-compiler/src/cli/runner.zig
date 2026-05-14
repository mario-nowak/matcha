const std = @import("std");
const build_options = @import("build_options");
const matcha = @import("matcha");

const Command = @import("command.zig").Command;
const parser = @import("parser.zig");

pub fn run(allocator: std.mem.Allocator, iter: anytype) !u8 {
    const command = try parser.parse(allocator, iter);

    switch (command) {
        .help => |topic| {
            try parser.writeHelp(topic);
            return 0;
        },
        .version => {
            try std.fs.File.stdout().deprecatedWriter().print("{s}\n", .{build_options.version});
            return 0;
        },
        .emit => |emit| {
            _ = try matcha.compiler.pipeline.emitFile(allocator, emit.input_path, emit.output_path);
            return 0;
        },
        .build => |build| {
            _ = try matcha.toolchain.buildFile(allocator, build.input_path, build.output_path);
            return 0;
        },
        .run => |run_command| {
            return try matcha.toolchain.runFile(allocator, run_command.input_path, run_command.program_arguments);
        },
    }
}
