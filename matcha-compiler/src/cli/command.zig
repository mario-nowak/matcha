pub const HelpTopic = enum {
    emit,
    build,
    run,
};

pub const Command = union(enum) {
    help: ?HelpTopic,
    version,
    emit: struct {
        input_path: []const u8,
        output_path: ?[]const u8,
    },
    build: struct {
        input_path: []const u8,
        output_path: ?[]const u8,
    },
    run: struct {
        input_path: []const u8,
        program_arguments: []const []const u8,
    },
};
