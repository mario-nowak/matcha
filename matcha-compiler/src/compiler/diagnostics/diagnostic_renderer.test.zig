const std = @import("std");
const diagnostics = @import("diagnostics");

pub const DiagnosticRenderer = struct {
    pub const render = struct {
        test "shows the path and line of the module that the diagnostic belongs to" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var source_registry = diagnostics.SourceRegistry.init(arena.allocator());
            _ = try source_registry.add("main.mt", "val main = 1;\n");
            const imported_module_id = try source_registry.add("imported.mt", "val imported = 2;\n");
            var output = std.Io.Writer.Allocating.init(arena.allocator());
            const diagnostic = diagnostics.Diagnostic{
                .severity = .@"error",
                .message = "something is wrong",
                .span = .{ .module_id = imported_module_id, .line = 1, .column = 5, .byte_offset = 4, .byte_len = 8 },
            };

            try diagnostics.DiagnosticRenderer.render(&output.writer, &source_registry, &.{diagnostic});

            try std.testing.expectEqualStrings(
                "error: something is wrong\n" ++
                    " --> imported.mt:1:5\n" ++
                    "   |\n" ++
                    " 1 | val imported = 2;\n" ++
                    "   |    ^^^^^^^^\n\n",
                output.written(),
            );
        }
    };
};
