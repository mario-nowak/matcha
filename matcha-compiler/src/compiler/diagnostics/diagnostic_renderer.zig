const std = @import("std");
const Diagnostic = @import("diagnostic.zig").Diagnostic;

pub const DiagnosticRenderer = struct {
    pub fn render(writer: anytype, input_path: []const u8, source: []const u8, diagnostics: []const Diagnostic) !void {
        for (diagnostics) |diagnostic| {
            try renderOne(writer, input_path, source, diagnostic);
        }
    }

    fn renderOne(writer: anytype, input_path: []const u8, source: []const u8, diagnostic: Diagnostic) !void {
        const severity_text = switch (diagnostic.severity) {
            .@"error" => "error",
        };

        const line_number = diagnostic.span.line;
        const column_number = diagnostic.span.column;
        const line_text = sliceLine(source, diagnostic.span.byte_offset);
        const gutter_width = digitCount(line_number);
        const caret_count = if (diagnostic.span.byte_len == 0) @as(usize, 1) else diagnostic.span.byte_len;
        const caret_padding = if (column_number > 0) column_number - 1 else 0;

        try writer.print("{s}: {s}\n", .{ severity_text, diagnostic.message });
        try writer.print(" --> {s}:{d}:{d}\n", .{ input_path, line_number, column_number });
        try writeGutter(writer, gutter_width, null);
        try writer.writeAll("\n");
        try writeGutter(writer, gutter_width, line_number);
        try writer.print(" {s}\n", .{line_text});
        try writeGutter(writer, gutter_width, null);
        try writeRepeated(writer, ' ', caret_padding);
        try writeRepeated(writer, '^', caret_count);
        try writer.writeAll("\n\n");
    }
};

pub fn renderStderr(input_path: []const u8, source: []const u8, diagnostics: []const Diagnostic) !void {
    const stderr = std.fs.File.stderr();
    try DiagnosticRenderer.render(stderr.deprecatedWriter(), input_path, source, diagnostics);
}

fn writeGutter(writer: anytype, gutter_width: usize, line_number: ?usize) !void {
    if (line_number) |value| {
        try writer.print(" {d: >[1]} |", .{ value, gutter_width });
        return;
    }

    try writer.print(" {s: >[1]} |", .{ "", gutter_width });
}

fn writeRepeated(writer: anytype, byte: u8, count: usize) !void {
    for (0..count) |_| {
        try writer.writeByte(byte);
    }
}

fn sliceLine(source: []const u8, byte_offset: usize) []const u8 {
    const safe_offset = @min(byte_offset, source.len);

    var line_start = safe_offset;
    while (line_start > 0 and source[line_start - 1] != '\n') {
        line_start -= 1;
    }

    var line_end = safe_offset;
    while (line_end < source.len and source[line_end] != '\n') {
        line_end += 1;
    }

    return source[line_start..line_end];
}

fn digitCount(value: usize) usize {
    if (value == 0) {
        return 1;
    }

    var current = value;
    var digits: usize = 0;
    while (current > 0) {
        current /= 10;
        digits += 1;
    }
    return digits;
}
