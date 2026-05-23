const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");

pub const RuntimeRepresentation = union(enum) {
    None,
    Present,
    Array: ArrayRuntimeRepresentation,

    pub fn hasRuntimeRepresentation(self: @This()) bool {
        return switch (self) {
            .None => false,
            .Present, .Array => true,
        };
    }
};

pub const ArrayRuntimeRepresentation = struct {
    element_type_id: typing.TypeId,
};

pub const RuntimeRepresentationByNodeId = std.AutoHashMap(ast.NodeId, RuntimeRepresentation);
pub const RuntimeRepresentationByTypeId = std.AutoHashMap(typing.TypeId, RuntimeRepresentation);

pub const RuntimeRepresentationResult = struct {
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,
    runtime_representation_by_type_id: RuntimeRepresentationByTypeId,
};
