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

pub fn parse(arena: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    const result = clap.parseEx(
        clap.Help,
        &top_level_params,
        top_level_parsers,
        argument_iterator,
        .{
            .allocator = arena,
            .diagnostic = &diagnostic,
            .terminating_positional = 0,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return error.InvalidCommandLine;
    };

    if (result.args.help != 0) {
        return .{ .help = null };
    }
    if (result.args.version != 0) {
        return .version;
    }

    const subcommand = result.positionals[0] orelse return .{ .help = null };
    return switch (subcommand) {
        .help => parseHelpCommand(arena, argument_iterator),
        .emit => parseEmitCommand(arena, argument_iterator),
        .build => parseBuildCommand(arena, argument_iterator),
        .run => parseRunCommand(arena, argument_iterator),
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

fn parseHelpCommand(arena: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    _ = clap.parseEx(
        clap.Help,
        &help_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = arena,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return error.InvalidCommandLine;
    };

    return .{ .help = null };
}

fn reportMissingInputPath() error{MissingInputPath} {
    std.fs.File.stderr().deprecatedWriter().print("error: missing input file\n", .{}) catch {};
    return error.MissingInputPath;
}

// The default output path is the input path without `.mt`, so an input without the extension would be overwritten.
fn validateInputPath(input_path: []const u8) !void {
    if (std.mem.eql(u8, std.fs.path.extension(input_path), ".mt")) {
        return;
    }
    try std.fs.File.stderr().deprecatedWriter().print("error: input file must have the .mt extension: {s}\n", .{input_path});
    return error.InputPathWithoutMatchaExtension;
}

fn parseEmitCommand(arena: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    const result = clap.parseEx(
        clap.Help,
        &command_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = arena,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return error.InvalidCommandLine;
    };

    if (result.args.help != 0) {
        return .{ .help = .emit };
    }

    const input_path = result.positionals[0] orelse return reportMissingInputPath();
    try validateInputPath(input_path);
    return .{ .emit = .{
        .input_path = input_path,
        .output_path = result.args.output,
    } };
}

fn parseBuildCommand(arena: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    const result = clap.parseEx(
        clap.Help,
        &command_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = arena,
            .diagnostic = &diagnostic,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return error.InvalidCommandLine;
    };

    if (result.args.help != 0) {
        return .{ .help = .build };
    }

    const input_path = result.positionals[0] orelse return reportMissingInputPath();
    try validateInputPath(input_path);
    return .{ .build = .{
        .input_path = input_path,
        .output_path = result.args.output,
    } };
}

fn parseRunCommand(arena: std.mem.Allocator, argument_iterator: anytype) !Command {
    var diagnostic = clap.Diagnostic{};
    const result = clap.parseEx(
        clap.Help,
        &run_params,
        clap.parsers.default,
        argument_iterator,
        .{
            .allocator = arena,
            .diagnostic = &diagnostic,
            .terminating_positional = 0,
        },
    ) catch |parsing_error| {
        try diagnostic.reportToFile(.stderr(), parsing_error);
        return error.InvalidCommandLine;
    };

    if (result.args.help != 0) {
        return .{ .help = .run };
    }

    const input_path = result.positionals[0] orelse return reportMissingInputPath();
    try validateInputPath(input_path);
    var program_arguments: std.ArrayList([]const u8) = .empty;

    if (argument_iterator.next()) |argument| {
        if (!std.mem.eql(u8, argument, "--")) {
            try program_arguments.append(arena, argument);
        }
    }

    while (argument_iterator.next()) |argument| {
        try program_arguments.append(arena, argument);
    }

    return .{ .run = .{
        .input_path = input_path,
        .program_arguments = try program_arguments.toOwnedSlice(arena),
    } };
}
