const std = @import("std");
const ast = @import("ast");

pub const ControlFlowValidationError = error{
    OutOfMemory,
    DiagnosticsEmitted,
};

pub const ExitBehavior = enum {
    FallsThroughWithValue,
    FallsThroughWithoutValue,
    Terminates,
};

pub const ExitBehaviorByNodeId = std.AutoHashMap(ast.NodeId, ExitBehavior);
