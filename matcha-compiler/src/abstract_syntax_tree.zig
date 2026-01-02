const std = @import("std");
const Token = @import("lexer.zig").Token;

pub const Node = union(enum) {
    ValueDeclaration: ValueDeclaration,
    BinaryExpression: BinaryExpression,
    UnaryExpression: UnaryExpression,
    Identifier: Token,
    Integer: Token,
    Block: Block,
    IfExpression: IfExpression,
    // Add more as needed
};

pub const ValueDeclaration = struct {
    val_token: Token,
    name: Token,
    type_annotation: ?TypeNode,
    value: *Node,
};

pub const BinaryExpression = struct {
    left: *Node,
    operator: Token,
    right: *Node,
};

pub const UnaryExpression = struct {
    operator: Token,
    operand: *Node,
};

pub const Block = struct {
    left_brace: Token,
    statements: []Node,
    right_brace: Token,
};

pub const IfExpression = struct {
    if_token: Token,
    condition: *Node,
    then_branch: *Block,
    else_branch: ?*Block,
};

// Placeholder for TypeNode until we implement types properly
pub const TypeNode = struct {
    name: Token,
};
