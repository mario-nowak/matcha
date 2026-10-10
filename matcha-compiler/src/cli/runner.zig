const std = @import("std");
const build_options = @import("build_options");
const matcha = @import("matcha");

const diagnostics = matcha.compiler.diagnostics;
const Command = @import("command.zig").Command;
const parser = @import("parser.zig");

pub fn run(arena: std.mem.Allocator, iter: anytype) !u8 {
    const command = try parser.parse(arena, iter);

    switch (command) {
        .help => |topic_command| {
            try parser.writeHelp(topic_command);
            return 0;
        },
        .version => {
            var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
            try stdout_writer.interface.print("{s}\n", .{build_options.version});
            return 0;
        },
        .emit => |emit_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(arena);
            var source_registry = diagnostics.SourceRegistry.init(arena);

            matcha.compiler.pipeline.emitFile(
                arena,
                emit_command.input_path,
                emit_command.output_path,
                &diagnostic_store,
                &source_registry,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    &source_registry,
                    &diagnostic_store,
                    compilation_error,
                );
            };
            return 0;
        },
        .build => |build_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(arena);
            var source_registry = diagnostics.SourceRegistry.init(arena);

            _ = matcha.toolchain.buildFile(
                arena,
                build_command.input_path,
                build_command.output_path,
                &diagnostic_store,
                &source_registry,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    &source_registry,
                    &diagnostic_store,
                    compilation_error,
                );
            };
            return 0;
        },
        .run => |run_command| {
            var diagnostic_store = diagnostics.DiagnosticStore.init(arena);
            var source_registry = diagnostics.SourceRegistry.init(arena);

            return matcha.toolchain.runFile(
                arena,
                run_command.input_path,
                run_command.program_arguments,
                &diagnostic_store,
                &source_registry,
            ) catch |compilation_error| {
                return try handleCompilationError(
                    &source_registry,
                    &diagnostic_store,
                    compilation_error,
                );
            };
        },
    }
}

/// Prints an error that no earlier step reported, so the CLI never exits without a message.
pub fn reportUnreportedError(run_error: anyerror) void {
    switch (run_error) {
        // These errors print their own message where they happen, because only that place knows the context.
        error.InvalidCommandLine,
        error.MissingInputPath,
        error.InputPathWithoutMatchaExtension,
        error.InputFileUnreadable,
        error.OutputFileUnwritable,
        error.ChildProcessFailed,
        error.DependencyLookupFailed,
        => {},
        else => {
            var stderr_writer = std.fs.File.stderr().writerStreaming(&.{});
            stderr_writer.interface.print("error: unexpected failure: {s}\n", .{@errorName(run_error)}) catch {};
        },
    }
}

fn handleCompilationError(
    source_registry: *const diagnostics.SourceRegistry,
    diagnostic_store: *diagnostics.DiagnosticStore,
    compilation_error: anyerror,
) !u8 {
    switch (compilation_error) {
        error.DiagnosticsEmitted => {
            try diagnostics.renderStderr(source_registry, diagnostic_store.items());
            return 1;
        },
        else => return compilation_error,
    }
}
