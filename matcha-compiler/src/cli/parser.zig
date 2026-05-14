const std = @import("std");
const clap = @import("clap");

const Command = @import("command.zig").Command;
const HelpTopic = @import("command.zig").HelpTopic;

const Subcommand = enum {
    help,
    emit,
    build,
    run,
};

const top_level_parsers = .{
    .command = clap.parsers.enumeration(Subcommand),
};

const top_level_params = clap.parseParamsComptime(
    \\-h, --help     Display this help and exit.
    \\-v, --version  Output version information and exit.
    \\<command>
    \\
);

const command_params = clap.parseParamsComptime(
    \\-h, --help            Display this help and exit.
    \\    --output <str>    Write output to this path.
    \\<str>
    \\
);

const help_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\
);

pub fn parse(allocator: std.mem.Allocator, iter: anytype) !Command {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &top_level_params, top_level_parsers, iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return .{ .help = null };
    }
    if (res.args.version != 0) {
        return .version;
    }

    const subcommand = res.positionals[0] orelse return .{ .help = null };
    return switch (subcommand) {
        .help => parseHelpCommand(allocator, iter),
        .emit => parseEmitCommand(allocator, iter),
        .build => parseBuildCommand(allocator, iter),
        .run => parseRunCommand(allocator, iter),
    };
}

pub fn writeHelp(topic: ?HelpTopic) !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (topic == null) {
        try stdout.writeAll(
            "Usage:\n" ++
                "  matcha\n" ++
                "  matcha help\n" ++
                "  matcha --help\n" ++
                "  matcha --version\n" ++
                "  matcha emit <input.mt> [--output <file.ll>]\n" ++
                "  matcha build <input.mt> [--output <binary>]\n" ++
                "  matcha run <input.mt> [-- <program args...>]\n\n" ++
                "Commands:\n" ++
                "  help     Show this help message\n" ++
                "  emit     Emit LLVM IR\n" ++
                "  build    Build a native binary\n" ++
                "  run      Build and run a native binary without keeping artifacts\n",
        );
        return;
    }

    switch (topic.?) {
        .emit => try clap.helpToFile(.stdout(), clap.Help, &command_params, .{}),
        .build => try clap.helpToFile(.stdout(), clap.Help, &command_params, .{}),
        .run => try stdout.writeAll(
            "Usage:\n" ++
                "  matcha run <input.mt> [-- <program args...>]\n\n" ++
                "Options:\n" ++
                "  -h, --help  Display this help and exit.\n",
        ),
    }
}

const run_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<str>
    \\
);

fn parseHelpCommand(allocator: std.mem.Allocator, iter: anytype) !Command {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &help_params, clap.parsers.default, iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    return .{ .help = null };
}

fn parseEmitCommand(allocator: std.mem.Allocator, iter: anytype) !Command {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &command_params, clap.parsers.default, iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return .{ .help = .emit };
    }

    const input_path = res.positionals[0] orelse return error.MissingInputPath;
    return .{ .emit = .{
        .input_path = input_path,
        .output_path = res.args.output,
    } };
}

fn parseBuildCommand(allocator: std.mem.Allocator, iter: anytype) !Command {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &command_params, clap.parsers.default, iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return .{ .help = .build };
    }

    const input_path = res.positionals[0] orelse return error.MissingInputPath;
    return .{ .build = .{
        .input_path = input_path,
        .output_path = res.args.output,
    } };
}

fn parseRunCommand(allocator: std.mem.Allocator, iter: anytype) !Command {
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &run_params, clap.parsers.default, iter, .{
        .allocator = allocator,
        .diagnostic = &diag,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return .{ .help = .run };
    }

    const input_path = res.positionals[0] orelse return error.MissingInputPath;
    var program_arguments: std.ArrayList([]const u8) = .empty;
    defer program_arguments.deinit(allocator);

    if (iter.next()) |argument| {
        if (!std.mem.eql(u8, argument, "--")) {
            try program_arguments.append(allocator, argument);
        }
    }

    while (iter.next()) |argument| {
        try program_arguments.append(allocator, argument);
    }

    return .{ .run = .{
        .input_path = input_path,
        .program_arguments = try program_arguments.toOwnedSlice(allocator),
    } };
}

test "parse bare invocation as help" {
    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "matcha");
    defer iter.deinit();
    _ = iter.next();

    const command = try parse(std.testing.allocator, &iter);
    try std.testing.expectEqualDeep(Command{ .help = null }, command);
}

test "parse build command with output" {
    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "matcha build examples/learning-matcha.mt --output zig-out/bin/learning-matcha",
    );
    defer iter.deinit();
    _ = iter.next();

    const command = try parse(std.testing.allocator, &iter);
    switch (command) {
        .build => |build| {
            try std.testing.expectEqualStrings("examples/learning-matcha.mt", build.input_path);
            try std.testing.expectEqualStrings("zig-out/bin/learning-matcha", build.output_path.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parse run command" {
    var iter = try std.process.ArgIteratorGeneral(.{}).init(std.testing.allocator, "matcha run examples/aoc-2024-01.mt");
    defer iter.deinit();
    _ = iter.next();

    const command = try parse(std.testing.allocator, &iter);
    switch (command) {
        .run => |run| {
            try std.testing.expectEqualStrings("examples/aoc-2024-01.mt", run.input_path);
            try std.testing.expectEqual(@as(usize, 0), run.program_arguments.len);
        },
        else => try std.testing.expect(false),
    }
}

test "parse run command with forwarded program arguments" {
    var iter = try std.process.ArgIteratorGeneral(.{}).init(
        std.testing.allocator,
        "matcha run examples/aoc-2024-01.mt -- examples/data/aoc-2024-01-input.txt --verbose",
    );
    defer iter.deinit();
    _ = iter.next();

    const command = try parse(std.testing.allocator, &iter);
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
