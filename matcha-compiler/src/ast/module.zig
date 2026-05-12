const std = @import("std");
const lexing = @import("lexing");
const type_expressions = @import("type_expressions");

pub const NodeId = u32;

pub const NodeKind = union(enum) {
    // Statements-ish nodes
    Declaration: Declaration,
    ItemDefinition: ItemDefinition,
    Return: Return,
    IfStatement: IfStatement,
    ExpressionStatement: ExpressionStatement,
    Assignment: Assignment,
    Loop: Loop,
    Leave: Leave,
    Continue: Continue,
    While: While,
    // Expressions-ish nodes
    IfExpression: IfExpression,
    MatchExpression: MatchExpression,
    CallExpression: CallExpression,
    MemberAccess: MemberAccess,
    BinaryExpression: BinaryExpression,
    UnaryExpression: UnaryExpression,
    Identifier: lexing.Token,
    IntegerLiteral: lexing.Token,
    BooleanLiteral: lexing.Token,
    StringLiteral: lexing.Token,
    Block: Block,
    StructureConstruction: StructureConstruction,
    AnonymousStructureLiteral: AnonymousStructureLiteral,
    ArrayLiteral: ArrayLiteral,
    IndexAccess: IndexAccess,
};

pub const Node = struct {
    id: NodeId,
    kind: NodeKind,
};

pub const ItemDefinition = struct {
    item_token: lexing.Token,
    identifier_token: lexing.Token,
    item: Item,
};

pub const Item = union(enum) {
    Function: Function,
    Structure: Structure,
};

pub const Structure = struct {
    structure_token: lexing.Token,
    fields: []Field,
    function_definitions: []Node,
};

pub const Field = struct {
    name: lexing.Token,
    type_annotation: *type_expressions.TypeExpression,
};

pub const Declaration = struct {
    val_token: lexing.Token,
    name: lexing.Token,
    type_annotation: ?*type_expressions.TypeExpression,
    value: *Node,
    binding_mutability: BindingMutability,
};

pub const Function = struct {
    parameters: []Parameter,
    return_type_annotation: *type_expressions.TypeExpression,
    body_expression: *Node,
};

pub const Parameter = struct {
    name: lexing.Token,
    type_annotation: *type_expressions.TypeExpression,
};

pub const Return = struct {
    return_token: lexing.Token,
    value: ?*Node,
};

pub const Assignment = struct {
    target: *Node,
    operator: AssignmentOperator,
    assignment_token: lexing.Token,
    value: *Node,
};

pub const AssignmentOperator = union(enum) {
    Assign,
    Compound: BinaryOperator,
};

pub const BindingMutability = enum {
    Mutable,
    Immutable,
};

pub const Loop = struct {
    loop_token: lexing.Token,
    body_block: *Node,
};

pub const Leave = struct {
    leave_token: lexing.Token,
};

pub const Continue = struct {
    continue_token: lexing.Token,
};

pub const While = struct {
    while_token: lexing.Token,
    condition: *Node,
    update: ?*Node,
    body_block: *Node,
};

pub const IfStatement = struct {
    if_token: lexing.Token,
    condition: *Node,
    then_branch: *Node,
};

pub const IfExpression = struct {
    if_token: lexing.Token,
    condition: *Node,
    then_block: *Node,
    else_token: lexing.Token,
    else_block: *Node,
};

pub const MatchArm = struct {
    pattern_or_condition: *Node,
    body: *Node,
    fat_arrow_token: lexing.Token,
};

pub const MatchExpression = struct {
    match_token: lexing.Token,
    subject: ?*Node,
    arms: []MatchArm,
    else_token: ?lexing.Token,
    else_arm: ?*Node,
};

pub const ExpressionStatement = struct {
    expression: *Node,
};

pub const CallExpression = struct {
    callee: *Node,
    left_parenthesis: lexing.Token,
    arguments: []Node,
    right_parenthesis: lexing.Token,
};

pub const MemberAccess = struct {
    base: *Node,
    dot_token: lexing.Token,
    member_name_token: lexing.Token,
};

pub const BinaryOperator = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
    And,
    Or,
};

pub const BinaryExpression = struct {
    left: *Node,
    operator: BinaryOperator,
    operator_token: lexing.Token,
    right: *Node,
};

pub const UnaryOperator = enum {
    Negate,
    Not,
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

pub const StructureConstruction = struct {
    structure_name: lexing.Token,
    fields: []StructureConstructionField,
};

pub const AnonymousStructureLiteral = struct {
    dot_token: lexing.Token,
    left_brace: lexing.Token,
    fields: []StructureConstructionField,
};

pub const StructureConstructionField = struct {
    name: lexing.Token,
    assign_token: lexing.Token,
    value: *Node,
};

pub const ArrayLiteral = struct {
    left_bracket: lexing.Token,
    elements: []Node,
    right_bracket: lexing.Token,
};

pub const IndexAccess = struct {
    base: *Node,
    left_bracket: lexing.Token,
    index: *Node,
    right_bracket: lexing.Token,
};

pub const Program = struct {
    statements: []Node,
};
