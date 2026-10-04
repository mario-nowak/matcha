const std = @import("std");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const DiagnosticSpan = @import("diagnostic_span.zig").DiagnosticSpan;

pub const DiagnosticStore = struct {
    arena: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
            .diagnostics = .{},
        };
    }

    fn emit(self: *@This(), diagnostic: Diagnostic) !void {
        try self.diagnostics.append(self.arena, diagnostic);
    }

    pub fn emitErrorFromSpan(self: *@This(), span: DiagnosticSpan, message: []const u8) !void {
        try self.emit(.{
            .severity = .@"error",
            .message = message,
            .span = span,
        });
    }

    pub fn emitErrorFromToken(self: *@This(), token: anytype, message: []const u8) !void {
        try self.emitErrorFromSpan(DiagnosticSpan.fromToken(token), message);
    }

    pub fn emitFormattedErrorFromToken(
        self: *@This(),
        arena: std.mem.Allocator,
        token: anytype,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        const message = try std.fmt.allocPrint(arena, format, args);
        try self.emitErrorFromToken(token, message);
    }

    pub fn items(self: *const @This()) []const Diagnostic {
        return self.diagnostics.items;
    }
};
