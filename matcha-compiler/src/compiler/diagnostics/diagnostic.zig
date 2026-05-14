const DiagnosticSpan = @import("diagnostic_span.zig").DiagnosticSpan;

pub const DiagnosticSeverity = enum {
    @"error",
};

pub const Diagnostic = struct {
    severity: DiagnosticSeverity,
    message: []const u8,
    span: DiagnosticSpan,
};
