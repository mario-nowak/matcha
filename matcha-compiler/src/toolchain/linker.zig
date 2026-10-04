const std = @import("std");
const builtin = @import("builtin");

const compiler = @import("compiler");
const diagnostics = compiler.diagnostics;

pub fn buildFile(
    arena: std.mem.Allocator,
    input_path: []const u8,
    output_path: ?[]const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) ![]const u8 {
    const llvm_ir = try compiler.pipeline.generateLlvmIrFromFile(arena, input_path, diagnostic_store);
    const binary_output_path = output_path orelse try compiler.pipeline.getDefaultBinaryOutputPath(arena, input_path);

    var temp_dir = try TemporaryDirectory.create(arena);
    defer temp_dir.delete();

    const llvm_ir_path = try std.fs.path.join(arena, &.{ temp_dir.path, "program.ll" });
    try compiler.pipeline.writeFile(llvm_ir_path, llvm_ir);

    try linkNativeBinary(arena, llvm_ir_path, binary_output_path);
    try std.fs.File.stdout().deprecatedWriter().print("built {s}\n", .{binary_output_path});
    return binary_output_path;
}

pub fn runFile(
    arena: std.mem.Allocator,
    input_path: []const u8,
    program_arguments: []const []const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) !u8 {
    const llvm_ir = try compiler.pipeline.generateLlvmIrFromFile(arena, input_path, diagnostic_store);

    var temporary_directory = try TemporaryDirectory.create(arena);
    defer temporary_directory.delete();

    const llvm_ir_path = try std.fs.path.join(arena, &.{ temporary_directory.path, "program.ll" });
    const binary_path = try std.fs.path.join(
        arena,
        &.{ temporary_directory.path, executableFileName("matcha-run") },
    );
    try compiler.pipeline.writeFile(llvm_ir_path, llvm_ir);
    try linkNativeBinary(arena, llvm_ir_path, binary_path);

    return runNativeBinary(arena, binary_path, program_arguments);
}

fn linkNativeBinary(arena: std.mem.Allocator, llvm_ir_path: []const u8, binary_output_path: []const u8) !void {
    const runtime_library_path = try resolveRuntimeLibraryPath(arena);

    if (std.fs.path.dirname(binary_output_path)) |directory| {
        try std.fs.cwd().makePath(directory);
    }

    var argv: std.ArrayList([]const u8) = .empty;

    try argv.appendSlice(arena, &.{
        "clang",
        "-target",
        compiler.pipeline.getLlvmTargetTriple(),
        llvm_ir_path,
        runtime_library_path,
    });
    try appendGarbageCollectorLinkerFlags(arena, &argv);
    try argv.appendSlice(arena, &.{
        "-o",
        binary_output_path,
    });

    try runChildProcess(arena, argv.items, .inherit);
}

fn appendGarbageCollectorLinkerFlags(arena: std.mem.Allocator, argv: *std.ArrayList([]const u8)) !void {
    switch (builtin.os.tag) {
        .macos => {
            const gc_prefix = try brewPrefix(arena, "bdw-gc");
            const gc_library_dir = try std.fs.path.join(arena, &.{ gc_prefix, "lib" });
            try argv.append(arena, try std.fmt.allocPrint(arena, "-L{s}", .{gc_library_dir}));
            try argv.append(arena, "-lgc");
        },
        .linux => {
            // Ubuntu's clang defaults to PIE executables, but the current runtime
            // static library is not built with PIE-compatible relocations.
            try argv.append(arena, "-no-pie");
            // Zig-generated objects omit GNU-stack metadata. Mark the final binary
            // explicitly so GNU ld does not infer an executable stack or warn.
            try argv.append(arena, "-Wl,-z,noexecstack");
            try argv.append(arena, "-lgc");
        },
        else => return error.UnsupportedHostPlatform,
    }
}

fn runNativeBinary(arena: std.mem.Allocator, binary_path: []const u8, program_arguments: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;

    try argv.append(arena, binary_path);
    try argv.appendSlice(arena, program_arguments);

    var child = std.process.Child.init(argv.items, arena);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    return switch (term) {
        .Exited => |code| code,
        else => 1,
    };
}

fn brewPrefix(arena: std.mem.Allocator, package_name: []const u8) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = arena,
        .argv = &.{ "brew", "--prefix", package_name },
        .max_output_bytes = 1024,
    }) catch |spawn_error| {
        try std.fs.File.stderr().deprecatedWriter().print("error: cannot start 'brew': {s}\n", .{@errorName(spawn_error)});
        return error.DependencyLookupFailed;
    };

    if (result.term != .Exited or result.term.Exited != 0) {
        try std.fs.File.stderr().deprecatedWriter().print("error: failed to resolve Homebrew prefix for {s}\n", .{package_name});
        return error.DependencyLookupFailed;
    }

    return arena.dupe(u8, std.mem.trimRight(u8, result.stdout, "\r\n"));
}

fn resolveRuntimeLibraryPath(arena: std.mem.Allocator) ![]const u8 {
    const self_exe_path = try std.fs.selfExePathAlloc(arena);
    const executable_directory = std.fs.path.dirname(self_exe_path) orelse return error.UnexpectedExecutablePath;
    const install_prefix = std.fs.path.dirname(executable_directory) orelse return error.UnexpectedExecutablePath;
    return std.fs.path.join(arena, &.{ install_prefix, "lib", "libmatcha_runtime.a" });
}

const ChildStdIo = enum {
    inherit,
};

fn runChildProcess(arena: std.mem.Allocator, argv: []const []const u8, stdio: ChildStdIo) !void {
    var child = std.process.Child.init(argv, arena);
    switch (stdio) {
        .inherit => {
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
        },
    }

    const stderr = std.fs.File.stderr().deprecatedWriter();
    const term = child.spawnAndWait() catch |spawn_error| {
        try stderr.print("error: cannot start '{s}': {s}\n", .{ argv[0], @errorName(spawn_error) });
        return error.ChildProcessFailed;
    };
    switch (term) {
        .Exited => |code| if (code != 0) {
            try stderr.print("error: '{s}' failed with exit code {d}\n", .{ argv[0], code });
            return error.ChildProcessFailed;
        },
        else => {
            try stderr.print("error: '{s}' terminated abnormally\n", .{argv[0]});
            return error.ChildProcessFailed;
        },
    }
}

const TemporaryDirectory = struct {
    arena: std.mem.Allocator,
    path: []const u8,

    fn create(arena: std.mem.Allocator) !TemporaryDirectory {
        const base_directory = std.process.getEnvVarOwned(arena, "TMPDIR") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try arena.dupe(u8, "/tmp"),
            else => return err,
        };
        const directory_name = try std.fmt.allocPrint(arena, "matcha-{x}", .{std.crypto.random.int(u64)});
        const path = try std.fs.path.join(arena, &.{ base_directory, directory_name });
        try std.fs.makeDirAbsolute(path);

        return .{
            .arena = arena,
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
