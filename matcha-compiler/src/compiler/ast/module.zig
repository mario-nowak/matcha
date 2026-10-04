const std = @import("std");
const lexing = @import("lexing");
const type_expressions = @import("type_expressions");

pub const NodeId = u32;

pub const Pattern = @import("pattern.zig").Pattern;
pub const PatternKind = @import("pattern.zig").PatternKind;
pub const IntegerLiteralPattern = @import("pattern.zig").IntegerLiteralPattern;
pub const CasePattern = @import("pattern.zig").CasePattern;
pub const PayloadBinding = @import("pattern.zig").PayloadBinding;

pub const NodeKind = union(enum) {
    // Statements-ish nodes
    binding_declaration: BindingDeclaration,
    item_definition: ItemDefinition,
    return_statement: ReturnStatement,
    if_statement: IfStatement,
    expression_statement: ExpressionStatement,
    assignment_statement: AssignmentStatement,
    loop: Loop,
    leave_statement: LeaveStatement,
    continue_statement: ContinueStatement,
    @"while": While,
    for_in: ForIn,
    // Expressions-ish nodes
    if_expression: IfExpression,
    match_expression: MatchExpression,
    subjectless_match_expression: SubjectlessMatchExpression,
    call_expression: CallExpression,
    member_expression: MemberExpression,
    implicit_member_expression: ImplicitMemberExpression,
    binary_expression: BinaryExpression,
    unary_expression: UnaryExpression,
    identifier: lexing.Token,
    integer_literal: lexing.Token,
    boolean_literal: lexing.Token,
    string_literal: lexing.Token,
    unit_literal: lexing.Token,
    block: Block,
    qualified_structure_literal: QualifiedStructureLiteral,
    structure_literal: StructureLiteral,
    array_literal: ArrayLiteral,
    index_expression: IndexExpression,
};

pub const Node = struct {
    id: NodeId,
    kind: NodeKind,

    pub fn primaryToken(self: *const @This()) lexing.Token {
        return switch (self.kind) {
            .binding_declaration => |binding_declaration| binding_declaration.name,
            .item_definition => |item_definition| item_definition.identifier_token,
            .return_statement => |return_statement| return_statement.return_token,
            .if_statement => |if_statement| if_statement.if_token,
            .expression_statement => |expression_statement| expression_statement.expression.primaryToken(),
            .assignment_statement => |assignment_statement| assignment_statement.assignment_token,
            .loop => |loop| loop.loop_token,
            .leave_statement => |leave_statement| leave_statement.leave_token,
            .continue_statement => |continue_statement| continue_statement.continue_token,
            .@"while" => |while_statement| while_statement.while_token,
            .for_in => |for_in| for_in.for_token,
            .if_expression => |if_expression| if_expression.if_token,
            .match_expression => |match_expression| match_expression.match_token,
            .subjectless_match_expression => |subjectless_match_expression| subjectless_match_expression.match_token,
            .call_expression => |call_expression| call_expression.left_parenthesis,
            .member_expression => |member_expression| member_expression.member_name_token,
            .implicit_member_expression => |implicit_call_expression| implicit_call_expression.member_name_token,
            .binary_expression => |binary_expression| binary_expression.operator_token,
            .unary_expression => |unary_expression| unary_expression.operator_token,
            .identifier => |token| token,
            .integer_literal => |token| token,
            .boolean_literal => |token| token,
            .string_literal => |token| token,
            .unit_literal => |token| token,
            .block => |block| block.left_brace,
            .qualified_structure_literal => |qualified_structure_literal| qualified_structure_literal.structure_name,
            .structure_literal => |structure_literal| structure_literal.dot_token,
            .array_literal => |array_literal| array_literal.left_bracket,
            .index_expression => |index_expression| index_expression.left_bracket,
        };
    }
};

pub const ItemDefinition = struct {
    item_token: lexing.Token,
    identifier_token: lexing.Token,
    definition: ItemDefinitionKind,
};

pub const ItemDefinitionKind = union(enum) {
    function: FunctionDefinition,
    structure: StructureDefinition,
    @"union": UnionDefinition,
};

pub const UnionDefinition = struct {
    union_token: lexing.Token,
    cases: []UnionCaseDeclaration,
    function_definitions: []Node,
};

pub const UnionCaseDeclaration = struct {
    name: lexing.Token,
    type_annotation: ?*type_expressions.TypeExpression,
};

pub const StructureDefinition = struct {
    structure_token: lexing.Token,
    fields: []StructureFieldDeclaration,
    function_definitions: []Node,
};

pub const StructureFieldDeclaration = struct {
    name: lexing.Token,
    type_annotation: *type_expressions.TypeExpression,
};

pub const BindingDeclaration = struct {
    val_token: lexing.Token,
    name: lexing.Token,
    type_annotation: ?*type_expressions.TypeExpression,
    value: *Node,
    binding_mutability: BindingMutability,
};

pub const FunctionDefinition = struct {
    parameters: []ParameterDeclaration,
    return_type_annotation: *type_expressions.TypeExpression,
    body_expression: *Node,
};

pub const ParameterDeclaration = struct {
    name: lexing.Token,
    type_annotation: *type_expressions.TypeExpression,
};

pub const ReturnStatement = struct {
    return_token: lexing.Token,
    value: ?*Node,
};

pub const AssignmentStatement = struct {
    target: *Node,
    operator: AssignmentOperator,
    assignment_token: lexing.Token,
    value: *Node,
};

pub const AssignmentOperator = union(enum) {
    assign,
    compound: BinaryOperator,
};

pub const BindingMutability = enum {
    mutable,
    immutable,
};

pub const Loop = struct {
    loop_token: lexing.Token,
    body_block: *Node,
};

pub const LeaveStatement = struct {
    leave_token: lexing.Token,
};

pub const ContinueStatement = struct {
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

pub const MatchExpression = struct {
    match_token: lexing.Token,
    subject: *Node,
    arms: []MatchArm,
    else_token: ?lexing.Token,
    else_arm_expression: ?*Node,
};

pub const MatchArm = struct {
    pattern: Pattern,
    fat_arrow_token: lexing.Token,
    body_expression: *Node,
};

pub const SubjectlessMatchExpression = struct {
    match_token: lexing.Token,
    arms: []SubjectlessMatchArm,
    else_token: ?lexing.Token,
    else_arm_expression: ?*Node,
};

pub const SubjectlessMatchArm = struct {
    condition: *Node,
    fat_arrow_token: lexing.Token,
    body_expression: *Node,
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

pub const MemberExpression = struct {
    base: *Node,
    dot_token: lexing.Token,
    member_name_token: lexing.Token,
};

pub const ImplicitMemberExpression = struct {
    dot_token: lexing.Token,
    member_name_token: lexing.Token,
};

pub const BinaryOperator = enum {
    add,
    subtract,
    multiply,
    divide,
    equal,
    not_equal,
    less_than,
    less_than_or_equal,
    greater_than,
    greater_than_or_equal,
    @"and",
    @"or",

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .add => "+",
            .subtract => "-",
            .multiply => "*",
            .divide => "/",
            .equal => "==",
            .not_equal => "!=",
            .less_than => "<",
            .less_than_or_equal => "<=",
            .greater_than => ">",
            .greater_than_or_equal => ">=",
            .@"and" => "and",
            .@"or" => "or",
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
    negate,
    not,

    pub fn name(self: @This()) []const u8 {
        return switch (self) {
            .negate => "-",
            .not => "not",
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

pub const UnionConstruction = struct {
    union_name: lexing.Token,
    value: ?*Node,
};

pub const QualifiedStructureLiteral = struct {
    structure_name: lexing.Token,
    fields: []StructureFieldInitializer,
};

pub const StructureLiteral = struct {
    dot_token: lexing.Token,
    left_brace: lexing.Token,
    fields: []StructureFieldInitializer,
};

pub const StructureFieldInitializer = struct {
    name: lexing.Token,
    assign_token: lexing.Token,
    value: *Node,
};

pub const ArrayLiteral = struct {
    left_bracket: lexing.Token,
    elements: []Node,
    right_bracket: lexing.Token,
};

pub const IndexExpression = struct {
    base: *Node,
    left_bracket: lexing.Token,
    index: *Node,
    right_bracket: lexing.Token,
};

pub const Program = struct {
    statements: []Node,
};
