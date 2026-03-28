const std = @import("std");
const lexing = @import("lexing");

pub const NodeId = u32;

pub const NodeKind = union(enum) {
    // Statements-ish nodes
    ValueDeclaration: ValueDeclaration,
    IfStatement: IfStatement,
    ExpressionStatement: ExpressionStatement,
    // Expressions-ish nodes
    IfExpression: IfExpression,
    BinaryExpression: BinaryExpression,
    UnaryExpression: UnaryExpression,
    Identifier: lexing.Token,
    IntegerLiteral: lexing.Token,
    BooleanLiteral: lexing.Token,
    Block: Block,
};

pub const Node = struct {
    id: NodeId,
    kind: NodeKind,
};

pub const ValueDeclaration = struct {
    val_token: lexing.Token,
    name: lexing.Token,
    type_annotation: ?TypeAnnotation,
    value: *Node,
};

pub const IfStatement = struct {
    if_token: lexing.Token,
    condition: *Node,
    then_branch: *Node,
    else_branch: ?IfStatementElseBranch,
};

pub const IfStatementElseBranch = struct {
    else_token: lexing.Token,
    else_block: *Node,
};

pub const ExpressionStatement = struct {
    expression: *Node,
};

pub const BinaryOperator = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
};

pub const BinaryExpression = struct {
    left: *Node,
    operator: BinaryOperator,
    operator_token: lexing.Token,
    right: *Node,
};

pub const UnaryOperator = enum {
    Negate,
};

pub const UnaryExpression = struct {
    operator: UnaryOperator,
    operator_token: lexing.Token,
    operand: *Node,
};

pub const Block = struct {
    left_brace: lexing.Token,
    statements: []Node,
    result: ?*Node,
    right_brace: lexing.Token,
};

pub const IfExpression = struct {
    if_token: lexing.Token,
    condition: *Node,
    then_block: *Node,
    else_token: lexing.Token,
    else_block: *Node,
};

pub const TypeAnnotation = struct {
    name_token: lexing.Token,
};

pub const Program = struct {
    statements: []Node,
};
