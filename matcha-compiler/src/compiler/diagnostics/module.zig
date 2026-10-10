const std = @import("std");

pub const DiagnosticSpan = @import("diagnostic_span.zig").DiagnosticSpan;
pub const Diagnostic = @import("diagnostic.zig").Diagnostic;
pub const DiagnosticSeverity = @import("diagnostic.zig").DiagnosticSeverity;
pub const DiagnosticStore = @import("diagnostic_store.zig").DiagnosticStore;
pub const DiagnosticRenderer = @import("diagnostic_renderer.zig").DiagnosticRenderer;
pub const renderStderr = @import("diagnostic_renderer.zig").renderStderr;
pub const ModuleId = @import("source_registry.zig").ModuleId;
pub const SourceFile = @import("source_registry.zig").SourceFile;
pub const SourceRegistry = @import("source_registry.zig").SourceRegistry;

/// The error of every compiler phase: the phase reported its problems to the `DiagnosticStore`, or memory ran out.
pub const CompileError = error{DiagnosticsEmitted} || std.mem.Allocator.Error;
