const std = @import("std");

/// The error of every compiler phase: the phase reported its problems to the `DiagnosticStore`, or memory ran out.
pub const CompileError = error{DiagnosticsEmitted} || std.mem.Allocator.Error;
