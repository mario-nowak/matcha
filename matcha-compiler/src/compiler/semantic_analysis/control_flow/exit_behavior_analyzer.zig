const std = @import("std");
const ast = @import("ast");
const type_expressions = @import("type_expressions");
const control_flow_types = @import("control_flow_types.zig");

const ControlFlowValidationError = control_flow_types.ControlFlowValidationError;
pub const ExitBehavior = control_flow_types.ExitBehavior;
pub const ExitBehaviorByNodeId = control_flow_types.ExitBehaviorByNodeId;

pub const ExitBehaviorAnalyzer = struct {
    exit_behavior_by_node_id: ExitBehaviorByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
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
            .ItemDefinition => |item_definition| switch (item_definition.item) {
                .Function => |function_definition| {
                    try self.validateFunctionReturnsValue(&function_definition);
                },
                .Structure => |structure| {
                    for (structure.function_definitions) |*function_definition_node| {
                        try self.validateFunctionReturnPathsInNode(function_definition_node);
                    }
                },
            },
            else => {},
        }
    }

    pub fn validateFunctionReturnsValue(self: *@This(), function_definition: *const ast.Function) ControlFlowValidationError!void {
        const result = try self.validateTerminatesWithValue(function_definition.body_expression);
        const is_unit_function = isUnitTypeExpression(function_definition.return_type_annotation);
        if (!is_unit_function and result == .FallsThroughWithoutValue) {
            std.debug.print("Semantic Error: Not all paths in the function return a value\n", .{});
            return ControlFlowValidationError.NotAllPathsReturnValue;
        }
    }

    pub fn validateTerminatesWithValue(
        self: *@This(),
        node: *const ast.Node,
    ) ControlFlowValidationError!ExitBehavior {
        return switch (node.kind) {
            .Return => try self.validateReturnNode(node),
            .Block => |block| try self.validateBlockNode(node, block),
            .Declaration => |declaration| try self.validateDeclarationNode(declaration),
            .ItemDefinition => ControlFlowValidationError.ItemDefinitionInNonTopLevel,
            .IfStatement => |if_statement| try self.validateIfStatementNode(node, if_statement),
            .StructureConstruction => |structure_construction| try self.validateStructureConstructionNode(node, structure_construction),
            .AnonymousStructureLiteral => |anonymous_structure_literal| try self.validateAnonymousStructureLiteralNode(node, anonymous_structure_literal),
            .ExpressionStatement => |expression_statement| try self.validateExpressionStatementNode(node, expression_statement),
            .Assignment => |assignment| try self.validateAssignmentNode(node, assignment),
            .Loop => |loop| try self.validateLoopNode(node, loop),
            .While => |while_statement| try self.validateWhileNode(node, while_statement),
            .ForIn => |for_in| try self.validateForInNode(node, for_in),
            .Leave => self.markNodeExitBehavior(node, .FallsThroughWithoutValue),
            .Continue => self.markNodeExitBehavior(node, .FallsThroughWithoutValue),
            .IfExpression => |if_expression| try self.validateIfExpressionNode(node, if_expression),
            .MatchExpression => |match_expression| try self.validateMatchExpressionNode(node, match_expression),
            .CallExpression => |call_expression| try self.validateCallExpressionNode(node, call_expression),
            .BinaryExpression => |binary_expression| try self.validateBinaryExpressionNode(node, binary_expression),
            .UnaryExpression => |unary_expression| try self.validateUnaryExpressionNode(node, unary_expression),
            .MemberAccess => |member_access| try self.validateMemberAccessNode(node, member_access),
            .ArrayLiteral => |array_literal| try self.validateArrayLiteralNode(node, array_literal),
            .IndexAccess => |index_access| try self.validateIndexAccessNode(node, index_access),
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            => self.markNodeExitBehavior(node, .FallsThroughWithValue),
        };
    }

    fn markNodeExitBehavior(self: *@This(), node: *const ast.Node, behavior: ExitBehavior) ExitBehavior {
        self.exit_behavior_by_node_id.put(node.id, behavior) catch unreachable;
        return behavior;
    }

    fn validateReturnNode(self: *@This(), node: *const ast.Node) ControlFlowValidationError!ExitBehavior {
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
            _ = self.markNodeExitBehavior(node, .FallsThroughWithValue);
            return self.validateTerminatesWithValue(result_node);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
    }

    fn validateDeclarationNode(self: *@This(), declaration: ast.Declaration) ControlFlowValidationError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(declaration.value);
        self.exit_behavior_by_node_id.put(declaration.value.id, result) catch unreachable;
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

    fn validateStructureConstructionNode(
        self: *@This(),
        node: *const ast.Node,
        structure_construction: ast.StructureConstruction,
    ) ControlFlowValidationError!ExitBehavior {
        for (structure_construction.fields) |field| {
            const result = try self.validateTerminatesWithValue(field.value);
            if (result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }
        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
    }

    fn validateAnonymousStructureLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        anonymous_structure_literal: ast.AnonymousStructureLiteral,
    ) ControlFlowValidationError!ExitBehavior {
        for (anonymous_structure_literal.fields) |field| {
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

    fn validateAssignmentNode(
        self: *@This(),
        node: *const ast.Node,
        assignment: ast.Assignment,
    ) ControlFlowValidationError!ExitBehavior {
        const target_result = try self.validateTerminatesWithValue(assignment.target);
        if (target_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const result = try self.validateTerminatesWithValue(assignment.value);
        self.exit_behavior_by_node_id.put(assignment.value.id, result) catch unreachable;
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
        if (match_expression.subject) |subject| {
            const subject_result = try self.validateTerminatesWithValue(subject);
            if (subject_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }
        }

        var saw_fallthrough_with_value = false;
        var saw_fallthrough_without_value = false;
        var any_arm_falls_through = false;

        for (match_expression.arms) |arm| {
            const pattern_result = try self.validateTerminatesWithValue(arm.pattern_or_condition);
            if (pattern_result == .Terminates) {
                return self.markNodeExitBehavior(node, .Terminates);
            }

            const body_result = try self.validateTerminatesWithValue(arm.body);
            switch (body_result) {
                .Terminates => {},
                .FallsThroughWithValue => {
                    any_arm_falls_through = true;
                    saw_fallthrough_with_value = true;
                },
                .FallsThroughWithoutValue => {
                    any_arm_falls_through = true;
                    saw_fallthrough_without_value = true;
                },
            }
        }

        if (match_expression.else_arm) |else_arm| {
            const else_result = try self.validateTerminatesWithValue(else_arm);
            switch (else_result) {
                .Terminates => {},
                .FallsThroughWithValue => {
                    any_arm_falls_through = true;
                    saw_fallthrough_with_value = true;
                },
                .FallsThroughWithoutValue => {
                    any_arm_falls_through = true;
                    saw_fallthrough_without_value = true;
                },
            }
        }

        if (!any_arm_falls_through) {
            return self.markNodeExitBehavior(node, .Terminates);
        }
        if (saw_fallthrough_without_value) {
            return self.markNodeExitBehavior(node, .FallsThroughWithoutValue);
        }

        return self.markNodeExitBehavior(node, .FallsThroughWithValue);
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

    fn validateMemberAccessNode(
        self: *@This(),
        node: *const ast.Node,
        member_access: ast.MemberAccess,
    ) ControlFlowValidationError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(member_access.base);
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

    fn validateIndexAccessNode(
        self: *@This(),
        node: *const ast.Node,
        index_access: ast.IndexAccess,
    ) ControlFlowValidationError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(index_access.base);
        if (base_result == .Terminates) {
            return self.markNodeExitBehavior(node, .Terminates);
        }

        const index_result = try self.validateTerminatesWithValue(index_access.index);
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
