const std = @import("std");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const DiagnosticSpan = @import("diagnostic_span.zig").DiagnosticSpan;

pub const DiagnosticStore = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .diagnostics = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.diagnostics.deinit(self.allocator);
    }

    pub fn emit(self: *@This(), diagnostic: Diagnostic) !void {
        try self.diagnostics.append(self.allocator, diagnostic);
    }

    pub fn emitErrorFromToken(self: *@This(), token: anytype, message: []const u8) !void {
        try self.emit(.{
            .severity = .@"error",
            .message = message,
            .span = DiagnosticSpan.fromToken(token),
        });
    }

    pub fn emitFormattedErrorFromToken(
        self: *@This(),
        allocator: std.mem.Allocator,
        token: anytype,
        comptime format: []const u8,
        args: anytype,
    ) !void {
        const message = try std.fmt.allocPrint(allocator, format, args);
        try self.emitErrorFromToken(token, message);
    }

    pub fn items(self: *const @This()) []const Diagnostic {
        return self.diagnostics.items;
    }
};
