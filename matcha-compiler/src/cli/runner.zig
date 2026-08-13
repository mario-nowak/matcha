const std = @import("std");
const build_options = @import("build_options");
const matcha = @import("matcha");

const diagnostics = matcha.compiler.diagnostics;
const Command = @import("command.zig").Command;
const parser = @import("parser.zig");

pub fn run(allocator: std.mem.Allocator, iter: anytype) !u8 {
    const command = try parser.parse(allocator, iter);

    switch (command) {
        .help => |topic_command| {
            try parser.writeHelp(topic_command);
            return 0;
        },
        .version => {
            try std.fs.File.stdout().deprecatedWriter().print("{s}\n", .{build_options.version});
            return 0;
        },
        .emit => |emit_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
            defer diagnostic_store.deinit();

            matcha.compiler.pipeline.emitFile(
                allocator,
                emit_command.input_path,
                emit_command.output_path,
                &diagnostic_store,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    allocator,
                    emit_command.input_path,
                    &diagnostic_store,
                    compilation_error,
                );
            };
            return 0;
        },
        .build => |build_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
            defer diagnostic_store.deinit();

            _ = matcha.toolchain.buildFile(
                allocator,
                build_command.input_path,
                build_command.output_path,
                &diagnostic_store,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    allocator,
                    build_command.input_path,
                    &diagnostic_store,
                    compilation_error,
                );
            };
            return 0;
        },
        .run => |run_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
            defer diagnostic_store.deinit();

            return matcha.toolchain.runFile(
                allocator,
                run_command.input_path,
                run_command.program_arguments,
                &diagnostic_store,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    allocator,
                    run_command.input_path,
                    &diagnostic_store,
                    compilation_error,
                );
            };
        },
    }
}

fn handleCompilationError(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
    compilation_error: anyerror,
) !u8 {
    switch (compilation_error) {
        error.DiagnosticsEmitted => {
            const source = try readSourceFile(allocator, input_path);
            defer allocator.free(source);
            try diagnostics.renderStderr(input_path, source, diagnostic_store.items());
            return 1;
        },
        else => return compilation_error,
    }
}

fn readSourceFile(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(input_path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}
