const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const type_expressions = @import("type_expressions");
const control_flow_types = @import("control_flow_types.zig");

pub const ExitBehavior = control_flow_types.ExitBehavior;
pub const ExitBehaviorByNodeId = control_flow_types.ExitBehaviorByNodeId;

pub const ExitBehaviorAnalyzer = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    arena: std.mem.Allocator,
    exit_behavior_by_node_id: ExitBehaviorByNodeId,
    // Whether a `leave` targets the innermost loop that is being analyzed.
    innermost_loop_has_leave: bool,

    pub fn init(arena: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{
            .diagnostic_store = diagnostic_store,
            .arena = arena,
            .exit_behavior_by_node_id = ExitBehaviorByNodeId.init(arena),
            .innermost_loop_has_leave = false,
        };
    }

    pub fn analyzeProgram(
        self: *@This(),
        program: *const ast.Module,
    ) CompileError!ExitBehaviorByNodeId {
        self.exit_behavior_by_node_id.clearRetainingCapacity();

        for (program.statements) |*statement| {
            try self.validateFunctionReturnPathsInNode(statement);
        }

        return self.exit_behavior_by_node_id;
    }

    fn validateFunctionReturnPathsInNode(
        self: *@This(),
        node: *const ast.Node,
    ) CompileError!void {
        switch (node.kind) {
            .item_definition => |item_definition| switch (item_definition.definition) {
                .function => |function_definition| {
                    try self.validateFunctionReturnsValue(item_definition.identifier_token, &function_definition);
                },
                .structure => |structure| {
                    for (structure.function_definitions) |*function_definition_node| {
                        try self.validateFunctionReturnPathsInNode(function_definition_node);
                    }
                },
                .@"union" => |union_definition| {
                    for (union_definition.function_definitions) |*function_definition_node| {
                        try self.validateFunctionReturnPathsInNode(function_definition_node);
                    }
                },
            },
            else => {},
        }
    }

    pub fn validateFunctionReturnsValue(self: *@This(), function_name_token: lexing.Token, function_definition: *const ast.FunctionDefinition) CompileError!void {
        const result = try self.validateTerminatesWithValue(function_definition.body_expression);
        const is_unit_function = isUnitTypeExpression(function_definition.return_type_annotation);
        if (!is_unit_function and result == .falls_through_without_value) {
            try self.diagnostic_store.emitErrorFromToken(function_name_token, "not all control-flow paths in this function return a value");
            return error.DiagnosticsEmitted;
        }
    }

    pub fn validateTerminatesWithValue(
        self: *@This(),
        node: *const ast.Node,
    ) CompileError!ExitBehavior {
        return switch (node.kind) {
            .return_statement => try self.validateReturnStatementNode(node),
            .block => |block| try self.validateBlockNode(node, block),
            .binding_declaration => |binding_declaration| try self.validateBindingDeclarationNode(binding_declaration),
            .item_definition => {
                try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "item definitions are only allowed at the top level");
                return error.DiagnosticsEmitted;
            },
            .if_statement => |if_statement| try self.validateIfStatementNode(node, if_statement),
            .qualified_structure_literal => |qualified_structure_literal| try self.validateQualifiedStructureLiteralNode(node, qualified_structure_literal),
            .structure_literal => |structure_literal| try self.validateStructureLiteralNode(node, structure_literal),
            .expression_statement => |expression_statement| try self.validateExpressionStatementNode(node, expression_statement),
            .assignment_statement => |assignment_statement| try self.validateAssignmentStatementNode(node, assignment_statement),
            .loop => |loop| try self.validateLoopNode(node, loop),
            .@"while" => |while_statement| try self.validateWhileNode(node, while_statement),
            .for_in => |for_in| try self.validateForInNode(node, for_in),
            .leave_statement => try self.validateLeaveStatementNode(node),
            .continue_statement => try self.markNodeExitBehavior(node, .falls_through_without_value),
            .if_expression => |if_expression| try self.validateIfExpressionNode(node, if_expression),
            .match_expression => |match_expression| try self.validateMatchExpressionNode(node, match_expression),
            .subjectless_match_expression => |subjectless_match_expression| try self.validateSubjectlessMatchExpressionNode(node, subjectless_match_expression),
            .call_expression => |call_expression| try self.validateCallExpressionNode(node, call_expression),
            .binary_expression => |binary_expression| try self.validateBinaryExpressionNode(node, binary_expression),
            .unary_expression => |unary_expression| try self.validateUnaryExpressionNode(node, unary_expression),
            .member_expression => |member_expression| try self.validateMemberExpressionNode(node, member_expression),
            .array_literal => |array_literal| try self.validateArrayLiteralNode(node, array_literal),
            .index_expression => |index_expression| try self.validateIndexExpressionNode(node, index_expression),
            .implicit_member_expression,
            .identifier,
            .integer_literal,
            .boolean_literal,
            .string_literal,
            .unit_literal,
            => try self.markNodeExitBehavior(node, .falls_through_with_value),
        };
    }

    fn markNodeExitBehavior(self: *@This(), node: *const ast.Node, behavior: ExitBehavior) !ExitBehavior {
        try self.exit_behavior_by_node_id.put(node.id, behavior);
        return behavior;
    }

    fn validateReturnStatementNode(self: *@This(), node: *const ast.Node) CompileError!ExitBehavior {
        return self.markNodeExitBehavior(node, .terminates);
    }

    fn validateBlockNode(self: *@This(), node: *const ast.Node, block: ast.Block) CompileError!ExitBehavior {
        for (block.statements) |*statement| {
            const result = try self.validateTerminatesWithValue(statement);
            if (result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }

        if (block.result) |result_node| {
            // A result expression that terminates on every path, e.g. an if-expression whose branches all return,
            // terminates the block as well.
            const result_behavior = try self.validateTerminatesWithValue(result_node);
            if (result_behavior == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
            _ = try self.markNodeExitBehavior(node, .falls_through_with_value);
            return result_behavior;
        }

        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    fn validateBindingDeclarationNode(self: *@This(), binding_declaration: ast.BindingDeclaration) CompileError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(binding_declaration.value);
        try self.exit_behavior_by_node_id.put(binding_declaration.value.id, result);
        return result;
    }

    fn validateIfStatementNode(
        self: *@This(),
        node: *const ast.Node,
        if_statement: ast.IfStatement,
    ) CompileError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(if_statement.condition);
        if (condition_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        _ = try self.validateTerminatesWithValue(if_statement.then_branch);
        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    fn validateQualifiedStructureLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        qualified_structure_literal: ast.QualifiedStructureLiteral,
    ) CompileError!ExitBehavior {
        for (qualified_structure_literal.fields) |field| {
            const result = try self.validateTerminatesWithValue(field.value);
            if (result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }
        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateStructureLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        structure_literal: ast.StructureLiteral,
    ) CompileError!ExitBehavior {
        for (structure_literal.fields) |field| {
            const result = try self.validateTerminatesWithValue(field.value);
            if (result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }
        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateExpressionStatementNode(
        self: *@This(),
        node: *const ast.Node,
        expression_statement: ast.ExpressionStatement,
    ) CompileError!ExitBehavior {
        const result = try self.validateTerminatesWithValue(expression_statement.expression);
        if (result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }
        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    fn validateAssignmentStatementNode(
        self: *@This(),
        node: *const ast.Node,
        assignment_statement: ast.AssignmentStatement,
    ) CompileError!ExitBehavior {
        const target_result = try self.validateTerminatesWithValue(assignment_statement.target);
        if (target_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        const result = try self.validateTerminatesWithValue(assignment_statement.value);
        try self.exit_behavior_by_node_id.put(assignment_statement.value.id, result);
        return result;
    }

    fn validateLeaveStatementNode(self: *@This(), node: *const ast.Node) CompileError!ExitBehavior {
        self.innermost_loop_has_leave = true;
        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    /// A `loop` only ends through `leave`. Without one, it never falls through: it returns or runs forever.
    fn validateLoopNode(self: *@This(), node: *const ast.Node, loop: ast.Loop) CompileError!ExitBehavior {
        const has_leave = try self.validateLoopBodyHasLeave(loop.body_block);
        return self.markNodeExitBehavior(node, if (has_leave) .falls_through_without_value else .terminates);
    }

    /// Analyzes a loop body and reports whether a `leave` in it targets this loop. A `leave` inside a nested loop
    /// targets the nested loop instead.
    fn validateLoopBodyHasLeave(self: *@This(), body_block: *const ast.Node) CompileError!bool {
        const outer_loop_has_leave = self.innermost_loop_has_leave;
        defer self.innermost_loop_has_leave = outer_loop_has_leave;

        self.innermost_loop_has_leave = false;
        _ = try self.validateTerminatesWithValue(body_block);
        return self.innermost_loop_has_leave;
    }

    fn validateWhileNode(
        self: *@This(),
        node: *const ast.Node,
        while_statement: ast.While,
    ) CompileError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(while_statement.condition);
        if (condition_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        if (while_statement.update) |update| {
            const update_result = try self.validateTerminatesWithValue(update);
            if (update_result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }

        _ = try self.validateLoopBodyHasLeave(while_statement.body_block);
        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    fn validateForInNode(self: *@This(), node: *const ast.Node, for_in: ast.ForIn) CompileError!ExitBehavior {
        const iterable_result = try self.validateTerminatesWithValue(for_in.iterable);
        if (iterable_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        _ = try self.validateLoopBodyHasLeave(for_in.body_block);
        return self.markNodeExitBehavior(node, .falls_through_without_value);
    }

    fn validateIfExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        if_expression: ast.IfExpression,
    ) CompileError!ExitBehavior {
        const condition_result = try self.validateTerminatesWithValue(if_expression.condition);
        if (condition_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        const then_result = try self.validateTerminatesWithValue(if_expression.then_block);
        const else_result = try self.validateTerminatesWithValue(if_expression.else_block);
        if (then_result == .terminates and else_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        if (then_result == .falls_through_without_value or else_result == .falls_through_without_value) {
            return self.markNodeExitBehavior(node, .falls_through_without_value);
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateMatchExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        match_expression: ast.MatchExpression,
    ) CompileError!ExitBehavior {
        const subject_result = try self.validateTerminatesWithValue(match_expression.subject);
        if (subject_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        var arms_exit_behavior: ExitBehavior = .terminates;
        for (match_expression.arms) |arm| {
            arms_exit_behavior = joinArmExitBehavior(arms_exit_behavior, try self.validateTerminatesWithValue(arm.body_expression));
        }
        if (match_expression.else_arm_expression) |else_arm_expression| {
            arms_exit_behavior = joinArmExitBehavior(arms_exit_behavior, try self.validateTerminatesWithValue(else_arm_expression));
        }

        return self.markNodeExitBehavior(node, arms_exit_behavior);
    }

    fn validateSubjectlessMatchExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        subjectless_match_expression: ast.SubjectlessMatchExpression,
    ) CompileError!ExitBehavior {
        var arms_exit_behavior: ExitBehavior = .terminates;
        for (subjectless_match_expression.arms) |arm| {
            const condition_result = try self.validateTerminatesWithValue(arm.condition);
            if (condition_result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }

            arms_exit_behavior = joinArmExitBehavior(arms_exit_behavior, try self.validateTerminatesWithValue(arm.body_expression));
        }
        if (subjectless_match_expression.else_arm_expression) |else_arm_expression| {
            arms_exit_behavior = joinArmExitBehavior(arms_exit_behavior, try self.validateTerminatesWithValue(else_arm_expression));
        }

        return self.markNodeExitBehavior(node, arms_exit_behavior);
    }

    fn validateCallExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        call_expression: ast.CallExpression,
    ) CompileError!ExitBehavior {
        const callee_result = try self.validateTerminatesWithValue(call_expression.callee);
        if (callee_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        for (call_expression.arguments) |*argument| {
            const argument_result = try self.validateTerminatesWithValue(argument);
            if (argument_result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateBinaryExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        binary_expression: ast.BinaryExpression,
    ) CompileError!ExitBehavior {
        const left_result = try self.validateTerminatesWithValue(binary_expression.left);
        if (left_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        const right_result = try self.validateTerminatesWithValue(binary_expression.right);
        if (right_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateUnaryExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        unary_expression: ast.UnaryExpression,
    ) CompileError!ExitBehavior {
        const operand_result = try self.validateTerminatesWithValue(unary_expression.operand);
        if (operand_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateMemberExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        member_expression: ast.MemberExpression,
    ) CompileError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(member_expression.base);
        if (base_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateArrayLiteralNode(
        self: *@This(),
        node: *const ast.Node,
        array_literal: ast.ArrayLiteral,
    ) CompileError!ExitBehavior {
        for (array_literal.elements) |*element| {
            const element_result = try self.validateTerminatesWithValue(element);
            if (element_result == .terminates) {
                return self.markNodeExitBehavior(node, .terminates);
            }
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }

    fn validateIndexExpressionNode(
        self: *@This(),
        node: *const ast.Node,
        index_expression: ast.IndexExpression,
    ) CompileError!ExitBehavior {
        const base_result = try self.validateTerminatesWithValue(index_expression.base);
        if (base_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        const index_result = try self.validateTerminatesWithValue(index_expression.index);
        if (index_result == .terminates) {
            return self.markNodeExitBehavior(node, .terminates);
        }

        return self.markNodeExitBehavior(node, .falls_through_with_value);
    }
};

fn isUnitTypeExpression(type_expression: *const type_expressions.TypeExpression) bool {
    return switch (type_expression.*) {
        .named => |named_type_expression| std.mem.eql(
            u8,
            named_type_expression.name_token.kind.identifier,
            "unit",
        ),
        .array => false,
    };
}

fn joinArmExitBehavior(current: ExitBehavior, arm_exit_behavior: ExitBehavior) ExitBehavior {
    if (current == .falls_through_without_value or arm_exit_behavior == .falls_through_without_value) {
        return .falls_through_without_value;
    }
    if (current == .falls_through_with_value or arm_exit_behavior == .falls_through_with_value) {
        return .falls_through_with_value;
    }

    return .terminates;
}
