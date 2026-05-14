const std = @import("std");
const ast = @import("ast");

pub const ControlFlowValidationError = error{
    LeaveUsedOutsideOfLoop,
    ContinueUsedOutsideOfLoop,
    ItemDefinitionInNonTopLevel,
    NotAllPathsReturnValue,
    ReturnWithoutValueInNonUnitFunction,
    ReturnUsedOutsideOfFunction,
};

pub const ExitBehavior = enum {
    FallsThroughWithValue,
    FallsThroughWithoutValue,
    Terminates,
};

pub const ExitBehaviorByNodeId = std.AutoHashMap(ast.NodeId, ExitBehavior);
