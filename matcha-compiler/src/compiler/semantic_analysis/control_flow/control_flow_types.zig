const std = @import("std");
const ast = @import("ast");

pub const ControlFlowValidationError = error{
    OutOfMemory,
    DiagnosticsEmitted,
};

/// Denotes the control flow exit behavior of a node.
/// A node can either terminate due to a return statement, fall through to the end with a value, or fall through to the
/// end without a value.
pub const ExitBehavior = enum {
    FallsThroughWithValue,
    FallsThroughWithoutValue,
    Terminates,
};

pub const ExitBehaviorByNodeId = std.AutoHashMap(ast.NodeId, ExitBehavior);
