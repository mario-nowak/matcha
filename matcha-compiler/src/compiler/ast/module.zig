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
    ForIn: ForIn,
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

    pub fn primaryToken(self: *const @This()) lexing.Token {
        return switch (self.kind) {
            .Declaration => |declaration| declaration.name,
            .ItemDefinition => |item_definition| item_definition.identifier_token,
            .Return => |return_statement| return_statement.return_token,
            .IfStatement => |if_statement| if_statement.if_token,
            .ExpressionStatement => |expression_statement| expression_statement.expression.primaryToken(),
            .Assignment => |assignment| assignment.assignment_token,
            .Loop => |loop| loop.loop_token,
            .Leave => |leave_statement| leave_statement.leave_token,
            .Continue => |continue_statement| continue_statement.continue_token,
            .While => |while_statement| while_statement.while_token,
            .ForIn => |for_in| for_in.for_token,
            .IfExpression => |if_expression| if_expression.if_token,
            .MatchExpression => |match_expression| match_expression.match_token,
            .CallExpression => |call_expression| call_expression.left_parenthesis,
            .MemberAccess => |member_access| member_access.member_name_token,
            .BinaryExpression => |binary_expression| binary_expression.operator_token,
            .UnaryExpression => |unary_expression| unary_expression.operator_token,
            .Identifier => |token| token,
            .IntegerLiteral => |token| token,
            .BooleanLiteral => |token| token,
            .StringLiteral => |token| token,
            .Block => |block| block.left_brace,
            .StructureConstruction => |structure_construction| structure_construction.structure_name,
            .AnonymousStructureLiteral => |anonymous_structure_literal| anonymous_structure_literal.dot_token,
            .ArrayLiteral => |array_literal| array_literal.left_bracket,
            .IndexAccess => |index_access| index_access.left_bracket,
        };
    }
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

pub const ForIn = struct {
    for_token: lexing.Token,
    item_name: lexing.Token,
    in_token: lexing.Token,
    iterable: *Node,
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

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .Add => "+",
            .Subtract => "-",
            .Multiply => "*",
            .Divide => "/",
            .Equal => "==",
            .NotEqual => "!=",
            .LessThan => "<",
            .LessThanOrEqual => "<=",
            .GreaterThan => ">",
            .GreaterThanOrEqual => ">=",
            .And => "and",
            .Or => "or",
        };
    }
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

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .Negate => "-",
            .Not => "not",
        };
    }
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
