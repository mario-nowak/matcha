const std = @import("std");
const sources = @import("sources");

const NodeId = @import("node.zig").NodeId;
const Node = @import("node.zig").Node;

pub const Module = struct {
    statements: []Node,
};

pub const Program = struct {
    /// The first module is the root module. Only the root module contains statements other than item definitions, and they form the body of `main`.
    modules: []Module,
    /// What each import item refers to.
    import_target_by_node_id: ImportTargetByNodeId,
};

pub const ImportTarget = union(enum) {
    module: sources.ModuleId,
    builtins,
};

pub const ImportTargetByNodeId = std.AutoHashMap(NodeId, ImportTarget);
