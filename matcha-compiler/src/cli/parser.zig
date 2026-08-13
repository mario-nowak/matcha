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

pub fn parse(allocator: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    var result = clap.parseEx(
        clap.Help,
        &top_level_params,
        top_level_parsers,
        argument_iterator,
        .{
            .allocator = allocator,
            .diagnostic = &diagnostic,
            .terminating_positional = 0,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return parsing_error;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        return .{ .help = null };
    }
    if (result.args.version != 0) {
        return .version;
    }

    const subcommand = result.positionals[0] orelse return .{ .help = null };
    return switch (subcommand) {
        .help => parseHelpCommand(allocator, argument_iterator),
        .emit => parseEmitCommand(allocator, argument_iterator),
        .build => parseBuildCommand(allocator, argument_iterator),
        .run => parseRunCommand(allocator, argument_iterator),
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

fn parseHelpCommand(allocator: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    var result = clap.parseEx(
        clap.Help,
        &help_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = allocator,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return parsing_error;
    };
    defer result.deinit();

    return .{ .help = null };
}

fn parseEmitCommand(allocator: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    var result = clap.parseEx(
        clap.Help,
        &command_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = allocator,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return parsing_error;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        return .{ .help = .emit };
    }

    const input_path = result.positionals[0] orelse return error.MissingInputPath;
    return .{ .emit = .{
        .input_path = input_path,
        .output_path = result.args.output,
    } };
}

fn parseBuildCommand(allocator: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    var result = clap.parseEx(
        clap.Help,
        &command_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = allocator,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return parsing_error;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        return .{ .help = .build };
    }

    const input_path = result.positionals[0] orelse return error.MissingInputPath;
    return .{ .build = .{
        .input_path = input_path,
        .output_path = result.args.output,
    } };
}

fn parseRunCommand(allocator: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    var result = clap.parseEx(
        clap.Help,
        &run_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = allocator,
            .diagnostic = &diagnostic,
            .terminating_positional = 0,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return parsing_error;
    };
    defer result.deinit();

    if (result.args.help != 0) {
        return .{ .help = .run };
    }

    const input_path = result.positionals[0] orelse return error.MissingInputPath;
    var program_arguments: std.ArrayList([]const u8) = .empty;
    defer program_arguments.deinit(allocator);

    if (argument_iterator.next()) |argument| {
        if (!std.mem.eql(u8, argument, "--")) {
            try program_arguments.append(allocator, argument);
        }
    }

    while (argument_iterator.next()) |argument| {
        try program_arguments.append(allocator, argument);
    }

    return .{ .run = .{
        .input_path = input_path,
        .program_arguments = try program_arguments.toOwnedSlice(allocator),
    } };
}
