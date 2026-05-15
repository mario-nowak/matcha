const std = @import("std");

const compiler_root = ".";
const matcha_binary_path = "zig-out/bin/matcha";

pub const Result = struct {
    allocator: std.mem.Allocator,
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: Result) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

pub const RunOptions = struct {
    stdin: ?[]const u8 = null,
    program_arguments: []const []const u8 = &.{},
};

pub fn runFile(file_path: []const u8) !Result {
    return runPath(std.testing.allocator, file_path, .{});
}

pub fn runFileWith(file_path: []const u8, options: RunOptions) !Result {
    return runPath(std.testing.allocator, file_path, options);
}

pub fn runSource(file_name: []const u8, source: []const u8) !Result {
    return runSourceWith(file_name, source, .{});
}

pub fn runSourceWith(file_name: []const u8, source: []const u8, options: RunOptions) !Result {
    const allocator = std.testing.allocator;

    var temp_dir = try TemporaryDirectory.create(allocator);
    defer temp_dir.delete();

    const file_path = try std.fs.path.join(allocator, &.{ temp_dir.path, file_name });
    defer allocator.free(file_path);

    var file = try std.fs.createFileAbsolute(file_path, .{});
    defer file.close();
    try file.writeAll(source);

    return runPath(allocator, file_path, options);
}

pub fn expectSuccessOutput(result: *const Result, expected_stdout: []const u8) !void {
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings(expected_stdout, result.stdout);
}

pub fn expectCompileDiagnostic(result: *const Result, expected_message: []const u8) !void {
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expectEqualStrings("", result.stdout);
    try expectContains(result.stderr, "error:");
    try expectContains(result.stderr, expected_message);
}

pub fn expectRuntimeError(result: *const Result, expected_message: []const u8) !void {
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expectEqualStrings("", result.stdout);
    try expectContains(result.stderr, expected_message);
}

pub fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        return;
    }

    std.debug.print(
        "expected output to contain:\n{s}\nfull output:\n{s}\n",
        .{ needle, haystack },
    );
    return error.ExpectedSubstringNotFound;
}

fn runPath(allocator: std.mem.Allocator, file_path: []const u8, options: RunOptions) !Result {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, matcha_binary_path);
    try argv.append(allocator, "run");
    try argv.append(allocator, file_path);

    if (options.program_arguments.len > 0) {
        try argv.append(allocator, "--");
        try argv.appendSlice(allocator, options.program_arguments);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = if (options.stdin == null) .Ignore else .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = compiler_root;

    try child.spawn();
    errdefer {
        _ = child.kill() catch {};
    }

    if (options.stdin) |stdin_bytes| {
        if (child.stdin) |stdin_file| {
            try stdin_file.writeAll(stdin_bytes);
            stdin_file.close();
            child.stdin = null;
        }
    }

    var stdout: std.ArrayList(u8) = .empty;
    errdefer stdout.deinit(allocator);
    var stderr: std.ArrayList(u8) = .empty;
    errdefer stderr.deinit(allocator);

    try child.collectOutput(allocator, &stdout, &stderr, 1024 * 1024);
    const term = try child.wait();

    const exit_code = switch (term) {
        .Exited => |code| code,
        else => return error.UnexpectedProcessTermination,
    };

    return .{
        .allocator = allocator,
        .exit_code = exit_code,
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
    };
}

const TemporaryDirectory = struct {
    allocator: std.mem.Allocator,
    path: []u8,

    fn create(allocator: std.mem.Allocator) !TemporaryDirectory {
        const base_directory = std.process.getEnvVarOwned(allocator, "TMPDIR") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "/tmp"),
            else => return err,
        };
        defer allocator.free(base_directory);

        const directory_name = try std.fmt.allocPrint(allocator, "matcha-e2e-{x}", .{std.crypto.random.int(u64)});
        defer allocator.free(directory_name);

        const path = try std.fs.path.join(allocator, &.{ base_directory, directory_name });
        try std.fs.makeDirAbsolute(path);

        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    fn delete(self: TemporaryDirectory) void {
        std.fs.deleteTreeAbsolute(self.path) catch {};
        self.allocator.free(self.path);
    }
};
