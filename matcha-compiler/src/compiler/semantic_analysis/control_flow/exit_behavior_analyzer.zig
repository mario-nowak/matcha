const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const type_expressions = @import("type_expressions");
const control_flow_types = @import("control_flow_types.zig");

const ControlFlowValidationError = control_flow_types.ControlFlowValidationError;
pub const ExitBehavior = control_flow_types.ExitBehavior;
pub const ExitBehaviorByNodeId = control_flow_types.ExitBehaviorByNodeId;

pub const ExitBehaviorAnalyzer = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    allocator: std.mem.Allocator,
    exit_behavior_by_node_id: ExitBehaviorByNodeId,

    pub fn init(allocator: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{
            .diagnostic_store = diagnostic_store,
            .allocator = allocator,
            .exit_behavior_by_node_id = ExitBehaviorByNodeId.init(allocator),
        };
    }

    pub fn analyzeProgram(
        self: *@This(),
        program: *const ast.Program,
    ) ControlFlowValidationError!ExitBehaviorByNodeId {
        self.exit_behavior_by_node_id.clearRetainingCapacity();

        for (program.statements) |*statement| {
            try self.validateFunctionReturnPathsInNode(statement);
        }

        return self.exit_behavior_by_node_id;
    }

    fn validateFunctionReturnPathsInNode(
        self: *@This(),
        node: *const ast.Node,
    ) ControlFlowValidationError!void {
        switch (node.kind) {
            .ItemDefinition => |item_definition| switch (item_definition.definition) {
                .Function => |function_definition| {
                    try self.validateFunctionReturnsValue(item_definition.identifier_token, &function_definition);
                },
                .Structure => |structure| {
                    for (structure.function_definitions) |*function_definition_node| {
                        try self.validateFunctionReturnPathsInNode(function_definition_node);
                    }
                },
                .Union => |union_definition| {
                    for (union_definition.function_definitions) |*function_definition_node| {
                        try self.validateFunctionReturnPathsInNode(function_definition_node);
                    }
                },
            },
            else => {},
        }
    }

    pub fn validateFunctionReturnsValue(self: *@This(), function_name_token: lexing.Token, function_definition: *const ast.FunctionDefinition) ControlFlowValidationError!void {
        const result = try self.validateTerminatesWithValue(function_definition.body_expression);
        const is_unit_function = isUnitTypeExpression(function_definition.return_type_annotation);
        if (!is_unit_function and result == .FallsThroughWithoutValue) {
            try self.diagnostic_store.emitErrorFromToken(function_name_token, "not all control-flow paths in this function return a value");
            return error.DiagnosticsEmitted;
        }
    }

    pub fn validateTerminatesWithValue(
        self: *@This(),
        node: *const ast.Node,
    ) ControlFlowValidationError!ExitBehavior {
        return switch (node.kind) {
            .ReturnStatement => try self.validateReturnStatementNode(node),
            .Block => |block| try self.validateBlockNode(node, block),
            .BindingDeclaration => |binding_declaration| try self.validateBindingDeclarationNode(binding_declaration),
            .ItemDefinition => {
                try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "item definitions are only allowed at the top level");
                return error.DiagnosticsEmitted;
            },
            .IfStatement => |if_statement| try self.validateIfStatementNode(node, if_statement),
            .QualifiedStructureLiteral => |qualified_structure_literal| try self.validateQualifiedStructureLiteralNode(node, qualified_structure_literal),
            .StructureLiteral => |structure_literal| try self.validateStructureLiteralNode(node, structure_literal),
            .ExpressionStatement => |expression_statement| try self.validateExpressionStatementNode(node, expression_statement),
            .AssignmentStatement => |assignment_statement| try self.validateAssignmentStatementNode(node, assignment_statement),
            .Loop => |loop| try self.validateLoopNode(node, loop),
            .While => |while_statement| try self.validateWhileNode(node, while_statement),
            .ForIn => |for_in| try self.validateForInNode(node, for_in),
            .LeaveStatement => self.markNodeExitBehavior(node, .FallsThroughWithoutValue),
            .ContinueStatement => self.markNodeExitBehavior(node, .FallsThroughWithoutValue),
            .IfExpression => |if_expression| try self.validateIfExpressionNode(node, if_expression),
            .MatchExpression => |match_expression| try self.validateMatchExpressionNode(node, match_expression),
            .SubjectlessMatchExpression => |subjectless_match_expression| try self.validateSubjectlessMatchExpressionNode(node, subjectless_match_expression),
            .CallExpression => |call_expression| try self.validateCallExpressionNode(node, call_expression),
            .BinaryExpression => |binary_expression| try self.validateBinaryExpressionNode(node, binary_expression),
            .UnaryExpression => |unary_expression| try self.validateUnaryExpressionNode(node, unary_expression),
            .MemberExpression => |member_expression| try self.validateMemberExpressionNode(node, member_expression),
            .ArrayLiteral => |array_literal| try self.validateArrayLiteralNode(node, array_literal),
            .IndexExpression => |index_expression| try self.validateIndexExpressionNode(node, index_expression),
            .ImplicitMemberExpression,
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .UnitLiteral,
            => self.markNodeExitBehavior(node, .FallsThroughWithValue),
        };
    }

    fn markNodeExitBehavior(self: *@This(), node: *const ast.Node, behavior: ExitBehavior) ExitBehavior {
        self.exit_behavior_by_node_id.put(node.id, behavior) catch unreachable;
        return behavior;
    }

    fn validateReturnStatementNode(self: *@This(), node: *const ast.Node) ControlFlowValidationError!ExitBehavior {
        return self.markNodeExitBehavior(node, .Terminates);
    }

    fn validateBlockNode(self: *@This(), node: *const ast.Node, block: ast.Block) ControlFlowValidationError!ExitBehavior {
        for (block.statements) |*statement| {
            const result = try self.validateTerminatesWithValue(statement);
            if (result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }

        if (block.result) |result_node| {
            // A result expression that terminates on every path, e.g. an if-expression whose branches all return,
            // terminates the block as well.
            const result_behavior = try self.validateTerminatesWithValue(result_node);
            if (result_behavior == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
            _ = self.markNodeExitBehavior(node, .FallsThroughWithValue);
            return result_behavior;
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateBindingDeclarationNode(self: *@This(), binding_declaration: ast.BindingDeclaration) ControlFlowValidationError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(binding_declaration.value);
        self.exit_behavior_by_node_id.put(binding_declaration.value.id, result) catch unreachable;
        return result;
    }

    fn validateIfStatementNode(
        self: *@This(),
        node: *const ast.Node,
        if_statement: ast.IfStatement,
    ) ControlFlowValidationError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(if_statement.condition);
        if (condition_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        _ = try self.validateTerminatesWithValue(if_statement.then_branch);
        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateQualifiedStructureLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        qualified_structure_literal: ast.QualifiedStructureLiteral,
    ) ControlFlowValidationError!ExitBehavior {
        for (qualified_structure_literal.fields) |field| {
            const result = try self.validateTerminatesWithValue(field.value);
            if (result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }
        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateStructureLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        structure_literal: ast.StructureLiteral,
    ) ControlFlowValidationError!ExitBehavior {
        for (structure_literal.fields) |field| {
            const result = try self.validateTerminatesWithValue(field.value);
            if (result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }
        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateExpressionStatementNode(
        self: *@This(),
        node: *const ast.Node,
        expression_statement: ast.ExpressionStatement,
    ) ControlFlowValidationError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(expression_statement.expression);
        if (result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }
        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateAssignmentStatementNode(
        self: *@This(),
        node: *const ast.Node,
        assignment_statement: ast.AssignmentStatement,
    ) ControlFlowValidationError!ExitBehavior {
        const target_result = try self.validateTerminatesWithValue(assignment_statement.target);
        if (target_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const result = try self.validateTerminatesWithValue(assignment_statement.value);
        self.exit_behavior_by_node_id.put(assignment_statement.value.id, result) catch unreachable;
        return result;
    }

    fn validateLoopNode(self: *@This(), node: *const ast.Node, loop: ast.Loop) ControlFlowValidationError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(loop.body_block);
        _ = self.markNodeExitBehavior(node, result);
        return result;
    }

    fn validateWhileNode(
        self: *@This(),
        node: *const ast.Node,
        while_statement: ast.While,
    ) ControlFlowValidationError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(while_statement.condition);
        if (condition_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        if (while_statement.update) |update| {
            const update_result = try self.validateTerminatesWithValue(update);
            if (update_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }

        _ = try self.validateTerminatesWithValue(while_statement.body_block);
        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateForInNode(self: *@This(), node: *const ast.Node, for_in: ast.ForIn) ControlFlowValidationError!ExitBehavior {
        const iterable_result = try self.validateTerminatesWithValue(for_in.iterable);
        if (iterable_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        _ = try self.validateTerminatesWithValue(for_in.body_block);
        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateIfExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        if_expression: ast.IfExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(if_expression.condition);
        if (condition_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const then_result = try self.validateTerminatesWithValue(if_expression.then_block);
        const else_result = try self.validateTerminatesWithValue(if_expression.else_block);
        if (then_result == .Terminates and else_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        if (then_result == .FallsThroughWithoutValue or else_result == .FallsThroughWithoutValue) {
            return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateMatchExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        match_expression: ast.MatchExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const subject_result = try self.validateTerminatesWithValue(match_expression.subject);
        if (subject_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        var arm_exit_behaviors = MatchArmExitBehaviors{};
        for (match_expression.arms) |arm| {
            arm_exit_behaviors.add(try self.validateTerminatesWithValue(arm.body));
        }
        if (match_expression.else_arm) |else_arm| {
            arm_exit_behaviors.add(try self.validateTerminatesWithValue(else_arm));
        }

        return self.markNodeExitBehavior(node, arm_exit_behaviors.combined());
    }

    fn validateSubjectlessMatchExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        subjectless_match_expression: ast.SubjectlessMatchExpression,
    ) ControlFlowValidationError!ExitBehavior {
        var arm_exit_behaviors = MatchArmExitBehaviors{};
        for (subjectless_match_expression.arms) |arm| {
            const condition_result = try self.validateTerminatesWithValue(arm.condition);
            if (condition_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }

            arm_exit_behaviors.add(try self.validateTerminatesWithValue(arm.body));
        }
        if (subjectless_match_expression.else_arm) |else_arm| {
            arm_exit_behaviors.add(try self.validateTerminatesWithValue(else_arm));
        }

        return self.markNodeExitBehavior(node, arm_exit_behaviors.combined());
    }

    fn validateCallExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        call_expression: ast.CallExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const callee_result = try self.validateTerminatesWithValue(call_expression.callee);
        if (callee_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        for (call_expression.arguments) |*argument| {
            const argument_result = try self.validateTerminatesWithValue(argument);
            if (argument_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateBinaryExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        binary_expression: ast.BinaryExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const left_result = try self.validateTerminatesWithValue(binary_expression.left);
        if (left_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const right_result = try self.validateTerminatesWithValue(binary_expression.right);
        if (right_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateUnaryExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        unary_expression: ast.UnaryExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const operand_result = try self.validateTerminatesWithValue(unary_expression.operand);
        if (operand_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateMemberExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        member_expression: ast.MemberExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(member_expression.base);
        if (base_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateArrayLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        array_literal: ast.ArrayLiteral,
    ) ControlFlowValidationError!ExitBehavior {
        for (array_literal.elements) |*element| {
            const element_result = try self.validateTerminatesWithValue(element);
            if (element_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateIndexExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        index_expression: ast.IndexExpression,
    ) ControlFlowValidationError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(index_expression.base);
        if (base_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const index_result = try self.validateTerminatesWithValue(index_expression.index);
        if (index_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }
};

fn isUnitTypeExpression(type_expression: *const type_expressions.TypeExpression) bool {
    return switch (type_expression.*) {
        .Named => |named_type_expression| std.mem.eql(
            u8,
            named_type_expression.name_token.kind.Identifier,
            "unit",
        ),
        .Array => false,
    };
}

const MatchArmExitBehaviors = struct {
    saw_fallthrough_with_value: bool = false,
    saw_fallthrough_without_value: bool = false,

    fn add(self: *@This(), arm_exit_behavior: ExitBehavior) void {
        switch (arm_exit_behavior) {
            .Terminates => {},
            .FallsThroughWithValue => self.saw_fallthrough_with_value = true,
            .FallsThroughWithoutValue => self.saw_fallthrough_without_value = true,
        }
    }

    fn combined(self: *const @This()) ExitBehavior {
        if (self.saw_fallthrough_without_value) {
            return .FallsThroughWithoutValue;
        }
        if (self.saw_fallthrough_with_value) {
            return .FallsThroughWithValue;
        }

        return .Terminates;
    }
};
