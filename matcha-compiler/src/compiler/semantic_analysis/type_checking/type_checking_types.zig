const typing = @import("typing");
const symbols = @import("symbols");
const control_flow_validation = @import("../control_flow/module.zig");

pub const NodeRoleExpressionKind = enum {
    value,
    callee,
};

pub const NodeRole = union(enum) {
    statement,
    expression: NodeRoleExpressionKind,

    pub fn isInCalleePosition(self: @This()) bool {
        return switch (self) {
            .statement => false,
            .expression => |expression| switch (expression) {
                .value => false,
                .callee => true,
            },
        };
    }
};

pub const ExhaustivenessClass = enum {
    boolean,
    @"union",
    integer_open,
    string_open,
};

/// Facts about the surrounding program that every node inherits from its parent unless a node explicitly overrides
/// them. Compare `ParentNodeExpectation`, which holds facts that only apply to a single parent-child edge.
pub const TypeCheckEnvironment = struct {
    // The declared return type of the innermost enclosing function. Return statements check their value against it.
    // Null at module level.
    function_return_type_id: ?typing.TypeId,

    pub fn copyWithFunctionReturnType(self: @This(), return_type_id: typing.TypeId) @This() {
        var updated = self;
        updated.function_return_type_id = return_type_id;
        return updated;
    }
};

/// What a parent node expects from one direct child: the role the child plays and, optionally, the type the parent
/// expects the child to produce. Unlike `TypeCheckEnvironment`, nothing in here is inherited by the child's own
/// children. Every node builds a fresh expectation for each child, or forwards its own with `forwarded()` to the one
/// child whose value becomes its own value.
pub const ParentNodeExpectation = struct {
    node_role: NodeRole,
    type_id: ?typing.TypeId,

    pub const as_statement: @This() = .{ .node_role = .statement, .type_id = null };
    pub const as_expression: @This() = .{ .node_role = .{ .expression = .value }, .type_id = null };

    pub fn asExpressionWithType(type_id: ?typing.TypeId) @This() {
        return .{ .node_role = .{ .expression = .value }, .type_id = type_id };
    }

    pub fn asCallee(type_id: ?typing.TypeId) @This() {
        return .{ .node_role = .{ .expression = .callee }, .type_id = type_id };
    }

    /// The expectation a node hands to the child that produces its value, e.g. a block to its result expression or an
    /// if-expression to its branches. The expected type is kept. A callee role is not: the child is a plain value
    /// position again.
    pub fn forwarded(self: @This()) @This() {
        return switch (self.node_role) {
            .statement => self,
            .expression => .{ .node_role = .{ .expression = .value }, .type_id = self.type_id },
        };
    }
};

pub const PlaceInfo = struct {
    type_id: typing.TypeId,
};

pub const TypeCheckResult = struct {
    type_store: typing.TypeStore,
    type_id_by_symbol_id: typing.TypeIdBySymbolId,
    type_id_by_node_id: typing.TypeIdByNodeId,
    member_access_by_node_id: typing.MemberAccessByNodeId,
    union_case_index_by_pattern_id: typing.UnionCaseIndexByPatternId,
};
