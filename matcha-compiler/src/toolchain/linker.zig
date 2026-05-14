const std = @import("std");

const compiler = @import("compiler");
const diagnostics = compiler.diagnostics;

pub fn buildFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: ?[]const u8, diagnostic_store: *diagnostics.DiagnosticStore) ![]const u8 {
    const llvm_ir = try compiler.pipeline.emitLlvmIrFromFile(allocator, input_path, diagnostic_store);
    const binary_output_path = output_path orelse try compiler.pipeline.defaultBinaryOutputPath(allocator, input_path);

    var temp_dir = try TemporaryDirectory.create(allocator);
    defer temp_dir.delete();

    const llvm_ir_path = try std.fs.path.join(allocator, &.{ temp_dir.path, "program.ll" });
    try compiler.pipeline.writeFile(llvm_ir_path, llvm_ir);

    try linkNativeBinary(allocator, llvm_ir_path, binary_output_path);
    try std.fs.File.stdout().deprecatedWriter().print("built {s}\n", .{binary_output_path});
    return binary_output_path;
}

pub fn runFile(allocator: std.mem.Allocator, input_path: []const u8, program_arguments: []const []const u8, diagnostic_store: *diagnostics.DiagnosticStore) !u8 {
    const llvm_ir = try compiler.pipeline.emitLlvmIrFromFile(allocator, input_path, diagnostic_store);

    var temp_dir = try TemporaryDirectory.create(allocator);
    defer temp_dir.delete();

    const llvm_ir_path = try std.fs.path.join(allocator, &.{ temp_dir.path, "program.ll" });
    const binary_path = try std.fs.path.join(allocator, &.{ temp_dir.path, executableFileName("matcha-run") });
    try compiler.pipeline.writeFile(llvm_ir_path, llvm_ir);
    try linkNativeBinary(allocator, llvm_ir_path, binary_path);
    return runNativeBinary(allocator, binary_path, program_arguments);
}

fn linkNativeBinary(allocator: std.mem.Allocator, llvm_ir_path: []const u8, binary_output_path: []const u8) !void {
    const runtime_library_path = try resolveRuntimeLibraryPath(allocator);
    const gc_prefix = try brewPrefix(allocator, "bdw-gc");
    const gc_library_dir = try std.fs.path.join(allocator, &.{ gc_prefix, "lib" });

    if (std.fs.path.dirname(binary_output_path)) |directory| {
        try std.fs.cwd().makePath(directory);
    }

    const argv = [_][]const u8{
        "clang",
        llvm_ir_path,
        runtime_library_path,
        try std.fmt.allocPrint(allocator, "-L{s}", .{gc_library_dir}),
        "-lgc",
        "-o",
        binary_output_path,
    };

    try runChildProcess(allocator, &argv, .inherit);
}

fn runNativeBinary(allocator: std.mem.Allocator, binary_path: []const u8, program_arguments: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, binary_path);
    try argv.appendSlice(allocator, program_arguments);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 1,
    };
}

fn brewPrefix(allocator: std.mem.Allocator, package_name: []const u8) ![]const u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "brew", "--prefix", package_name },
        .max_output_bytes = 1024,
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        try std.fs.File.stderr().deprecatedWriter().print("error: failed to resolve Homebrew prefix for {s}\n", .{package_name});
        return error.DependencyLookupFailed;
    }

    return allocator.dupe(u8, std.mem.trimRight(u8, result.stdout, "\r\n"));
}

fn resolveRuntimeLibraryPath(allocator: std.mem.Allocator) ![]const u8 {
    const self_exe_path = try std.fs.selfExePathAlloc(allocator);
    const executable_directory = std.fs.path.dirname(self_exe_path) orelse return error.UnexpectedExecutablePath;
    const install_prefix = std.fs.path.dirname(executable_directory) orelse return error.UnexpectedExecutablePath;
    return std.fs.path.join(allocator, &.{ install_prefix, "lib", "libmatcha_runtime.a" });
}

const ChildStdIo = enum {
    inherit,
};

fn runChildProcess(allocator: std.mem.Allocator, argv: []const []const u8, stdio: ChildStdIo) !void {
    var child = std.process.Child.init(argv, allocator);
    switch (stdio) {
        .inherit => {
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
        },
    }

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.ChildProcessFailed,
        else => return error.ChildProcessFailed,
    }
}

const TemporaryDirectory = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    fn create(allocator: std.mem.Allocator) !TemporaryDirectory {
        const base_directory = std.process.getEnvVarOwned(allocator, "TMPDIR") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "/tmp"),
            else => return err,
        };
        const directory_name = try std.fmt.allocPrint(allocator, "matcha-{x}", .{std.crypto.random.int(u64)});
        const path = try std.fs.path.join(allocator, &.{ base_directory, directory_name });
        try std.fs.makeDirAbsolute(path);

        return .{
            .allocator = allocator,
            .path = path,
        };
    }

    fn delete(self: TemporaryDirectory) void {
        std.fs.deleteTreeAbsolute(self.path) catch {};
    }
};

fn executableFileName(name: []const u8) []const u8 {
    return switch (@import("builtin").os.tag) {
        .windows => name ++ ".exe",
        else => name,
    };
}
