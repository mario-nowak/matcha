const typing = @import("typing");
const symbols = @import("symbols");
const control_flow_validation = @import("../control_flow/module.zig");

pub const ValidationContext = enum {
    Statement,
    Expression,
    FunctionBody,
};

pub const ExhaustivenessClass = enum {
    Boolean,
    IntegerOpen,
    StringOpen,
    Subjectless,
};

pub const TypeError = error{
    OutOfMemory,
    DiagnosticsEmitted,
};

pub const TypeCheckEnvironment = struct {
    resolved_program: *const symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    context: ValidationContext,
    contextual_type_id: ?typing.TypeId,

    pub fn withContext(self: @This(), context: ValidationContext) @This() {
        var updated = self;
        updated.context = context;
        return updated;
    }

    pub fn withContextAndType(
        self: @This(),
        context: ValidationContext,
        contextual_type_id: ?typing.TypeId,
    ) @This() {
        var updated = self;
        updated.context = context;
        updated.contextual_type_id = contextual_type_id;
        return updated;
    }
};

pub const PlaceInfo = struct {
    type_id: typing.TypeId,
};
