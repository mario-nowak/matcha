const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const control_flow_types = @import("control_flow_types.zig");

const ControlFlowValidationError = control_flow_types.ControlFlowValidationError;

const ControlFlowValidationContext = struct {
    loop_depth: u32 = 0,
    scope_depth: u32 = 0,
    in_function: bool = false,
};

pub const StructuralValidator = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,

    pub fn init(diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{ .diagnostic_store = diagnostic_store };
    }

    pub fn validateProgram(
        self: *@This(),
        program: *const ast.Program,
    ) ControlFlowValidationError!void {
        const context = ControlFlowValidationContext{};
        for (program.statements) |*statement| {
            try self.validateNode(statement, &context);
        }
    }

    fn validateNode(
        self: *@This(),
        node: *const ast.Node,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        switch (node.kind) {
            .BindingDeclaration => |binding_declaration| try self.validateBindingDeclaration(binding_declaration, context),
            .ItemDefinition => |item_definition| try self.validateItemDefinition(item_definition, context),
            .ReturnStatement => |return_statement| try self.validateReturnStatement(return_statement, context),
            .AssignmentStatement => |assignment_statement| try self.validateAssignmentStatement(assignment_statement, context),
            .Loop => |loop| try self.validateLoop(loop, context),
            .QualifiedStructureLiteral => |qualified_structure_literal| try self.validateQualifiedStructureLiteral(qualified_structure_literal, context),
            .StructureLiteral => |structure_literal| try self.validateStructureLiteral(structure_literal, context),
            .While => |while_statement| try self.validateWhile(while_statement, context),
            .ForIn => |for_in| try self.validateForIn(for_in, context),
            .ContinueStatement => |continue_statement| try self.validateContinueStatement(continue_statement, context),
            .LeaveStatement => |leave_statement| try self.validateLeaveStatement(leave_statement, context),
            .IfStatement => |if_statement| try self.validateIfStatement(if_statement, context),
            .IfExpression => |if_expression| try self.validateIfExpression(if_expression, context),
            .MatchExpression => |match_expression| try self.validateMatchExpression(match_expression, context),
            .ExpressionStatement => |expression_statement| try self.validateExpressionStatement(expression_statement, context),
            .CallExpression => |call_expression| try self.validateCallExpression(call_expression, context),
            .BinaryExpression => |binary_expression| try self.validateBinaryExpression(binary_expression, context),
            .UnaryExpression => |unary_expression| try self.validateUnaryExpression(unary_expression, context),
            .MemberExpression => |member_expression| try self.validateMemberExpression(member_expression, context),
            .ArrayLiteral => |array_literal| try self.validateArrayLiteral(array_literal, context),
            .IndexExpression => |index_expression| try self.validateIndexExpression(index_expression, context),
            .Block => |block| try self.validateBlock(block, context),
            .ImplicitMemberExpression,
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .UnitLiteral,
            => {},
        }
    }

    fn validateBindingDeclaration(
        self: *@This(),
        binding_declaration: ast.BindingDeclaration,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(binding_declaration.value, context);
    }

    fn validateItemDefinition(
        self: *@This(),
        item_definition: ast.ItemDefinition,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        if (context.scope_depth > 0) {
            try self.diagnostic_store.emitErrorFromToken(item_definition.item_token, "item definitions are only allowed at the top level");
            return error.DiagnosticsEmitted;
        }

        switch (item_definition.definition) {
            .Function => |function_definition| {
                const function_context = ControlFlowValidationContext{
                    .loop_depth = 0,
                    .scope_depth = 0,
                    .in_function = true,
                };
                try self.validateNode(function_definition.body_expression, &function_context);
            },
            .Structure => |structure_definition| {
                for (structure_definition.function_definitions) |*function_definition_node| {
                    try self.validateNode(function_definition_node, context);
                }
            },
            .Union => |union_definition| {
                for (union_definition.function_definitions) |*function_definition_node| {
                    try self.validateNode(function_definition_node, context);
                }
            },
        }
    }

    fn validateReturnStatement(
        self: *@This(),
        return_statement: ast.ReturnStatement,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        if (!context.in_function) {
            try self.diagnostic_store.emitErrorFromToken(return_statement.return_token, "return statements are only allowed inside functions");
            return error.DiagnosticsEmitted;
        }
        if (return_statement.value) |expression| {
            try self.validateNode(expression, context);
        }
    }

    fn validateAssignmentStatement(
        self: *@This(),
        assignment_statement: ast.AssignmentStatement,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(assignment_statement.target, context);
        try self.validateNode(assignment_statement.value, context);
    }

    fn validateLoop(
        self: *@This(),
        loop: ast.Loop,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        const loop_context = ControlFlowValidationContext{
            .loop_depth = context.loop_depth + 1,
            .scope_depth = context.scope_depth,
            .in_function = context.in_function,
        };
        try self.validateNode(loop.body_block, &loop_context);
    }

    fn validateQualifiedStructureLiteral(
        self: *@This(),
        qualified_structure_literal: ast.QualifiedStructureLiteral,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        for (qualified_structure_literal.fields) |field| {
            try self.validateNode(field.value, context);
        }
    }

    fn validateStructureLiteral(
        self: *@This(),
        structure_literal: ast.StructureLiteral,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        for (structure_literal.fields) |field| {
            try self.validateNode(field.value, context);
        }
    }

    fn validateWhile(
        self: *@This(),
        while_statement: ast.While,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(while_statement.condition, context);
        if (while_statement.update) |update| {
            try self.validateNode(update, context);
        }

        const loop_context = ControlFlowValidationContext{
            .loop_depth = context.loop_depth + 1,
            .scope_depth = context.scope_depth,
            .in_function = context.in_function,
        };
        try self.validateNode(while_statement.body_block, &loop_context);
    }

    fn validateForIn(
        self: *@This(),
        for_in: ast.ForIn,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(for_in.iterable, context);

        const loop_context = ControlFlowValidationContext{
            .loop_depth = context.loop_depth + 1,
            .scope_depth = context.scope_depth,
            .in_function = context.in_function,
        };
        try self.validateNode(for_in.body_block, &loop_context);
    }

    fn validateContinueStatement(self: *@This(), continue_statement: ast.ContinueStatement, context: *const ControlFlowValidationContext) ControlFlowValidationError!void {
        if (context.loop_depth == 0) {
            try self.diagnostic_store.emitErrorFromToken(continue_statement.continue_token, "continue is only allowed inside loops");
            return error.DiagnosticsEmitted;
        }
    }

    fn validateLeaveStatement(self: *@This(), leave_statement: ast.LeaveStatement, context: *const ControlFlowValidationContext) ControlFlowValidationError!void {
        if (context.loop_depth == 0) {
            try self.diagnostic_store.emitErrorFromToken(leave_statement.leave_token, "leave is only allowed inside loops");
            return error.DiagnosticsEmitted;
        }
    }

    fn validateIfStatement(
        self: *@This(),
        if_statement: ast.IfStatement,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(if_statement.condition, context);
        try self.validateNode(if_statement.then_branch, context);
    }

    fn validateIfExpression(
        self: *@This(),
        if_expression: ast.IfExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(if_expression.condition, context);
        try self.validateNode(if_expression.then_block, context);
        try self.validateNode(if_expression.else_block, context);
    }

    fn validateMatchExpression(
        self: *@This(),
        match_expression: ast.MatchExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        if (match_expression.subject) |subject| {
            try self.validateNode(subject, context);
        }
        for (match_expression.arms) |arm| {
            try self.validateNode(arm.pattern_or_condition, context);
            try self.validateNode(arm.body, context);
        }
        if (match_expression.else_arm) |else_arm| {
            try self.validateNode(else_arm, context);
        }
    }

    fn validateExpressionStatement(
        self: *@This(),
        expression_statement: ast.ExpressionStatement,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(expression_statement.expression, context);
    }

    fn validateCallExpression(
        self: *@This(),
        call_expression: ast.CallExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(call_expression.callee, context);
        for (call_expression.arguments) |*argument| {
            try self.validateNode(argument, context);
        }
    }

    fn validateBinaryExpression(
        self: *@This(),
        binary_expression: ast.BinaryExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(binary_expression.left, context);
        try self.validateNode(binary_expression.right, context);
    }

    fn validateUnaryExpression(
        self: *@This(),
        unary_expression: ast.UnaryExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(unary_expression.operand, context);
    }

    fn validateMemberExpression(
        self: *@This(),
        member_expression: ast.MemberExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(member_expression.base, context);
    }

    fn validateArrayLiteral(
        self: *@This(),
        array_literal: ast.ArrayLiteral,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        for (array_literal.elements) |*element| {
            try self.validateNode(element, context);
        }
    }

    fn validateIndexExpression(
        self: *@This(),
        index_expression: ast.IndexExpression,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        try self.validateNode(index_expression.base, context);
        try self.validateNode(index_expression.index, context);
    }

    fn validateBlock(
        self: *@This(),
        block: ast.Block,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        const block_context = ControlFlowValidationContext{
            .loop_depth = context.loop_depth,
            .scope_depth = context.scope_depth + 1,
            .in_function = context.in_function,
        };
        for (block.statements) |*statement| {
            try self.validateNode(statement, &block_context);
        }
        if (block.result) |result_node| {
            try self.validateNode(result_node, &block_context);
        }
    }
};
