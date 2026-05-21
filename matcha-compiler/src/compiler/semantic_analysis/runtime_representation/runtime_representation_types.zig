const std = @import("std");
const ast = @import("ast");

pub const RuntimeRepresentation = enum {
    None,
    Present,
};

pub const RuntimeRepresentationByNodeId = std.AutoHashMap(ast.NodeId, RuntimeRepresentation);

pub const RuntimeRepresentationResult = struct {
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,
};
