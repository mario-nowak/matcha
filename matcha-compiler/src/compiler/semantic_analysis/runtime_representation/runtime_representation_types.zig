const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");

/// The target representation of a node at runtime. Nodes without a runtime representation (e.g. nodes of the `unit`
/// type) should not exist at runtime.
pub const RuntimeRepresentation = union(enum) {
    None,
    Present,

    pub fn hasRuntimeRepresentation(self: @This()) bool {
        return switch (self) {
            .None => false,
            .Present => true,
        };
    }
};

pub const RuntimeRepresentationByNodeId = std.AutoHashMap(ast.NodeId, RuntimeRepresentation);
pub const RuntimeRepresentationByTypeId = std.AutoHashMap(typing.TypeId, RuntimeRepresentation);

pub const RuntimeRepresentationResult = struct {
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,
    runtime_representation_by_type_id: RuntimeRepresentationByTypeId,
};
