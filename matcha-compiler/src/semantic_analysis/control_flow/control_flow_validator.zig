pub const ast = @import("ast");

pub const ControlFlowValidationError = error{
    LeaveUsedOutsideOfLoop,
    ContinueUsedOutsideOfLoop,
};

pub const ControlFlowValidationContext = struct {
    loop_depth: u32 = 0,
};

pub const ControlFlowValidator = struct {
    pub fn validateProgram(self: *@This(), program: *const ast.Program) ControlFlowValidationError!void {
        const context = ControlFlowValidationContext{};
        for (program.statements) |*statement| {
            try self.validateNode(statement, &context);
        }
    }

    pub fn validateNode(
        self: *@This(),
        node: *const ast.Node,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        switch (node.kind) {
            .Declaration => |declaration| {
                try self.validateNode(declaration.value, context);
            },
            .Assignment => |assignment| {
                try self.validateNode(assignment.value, context);
            },
            .Loop => |loop| {
                const loop_context = ControlFlowValidationContext{ .loop_depth = context.loop_depth + 1 };
                for (loop.statements) |*statement| {
                    try self.validateNode(statement, &loop_context);
                }
            },
            .Continue => {
                if (context.loop_depth == 0) {
                    return ControlFlowValidationError.ContinueUsedOutsideOfLoop;
                }
            },
            .Leave => {
                if (context.loop_depth == 0) {
                    return ControlFlowValidationError.LeaveUsedOutsideOfLoop;
                }
            },
            .IfStatement => |if_statement| {
                try self.validateNode(if_statement.condition, context);
                try self.validateNode(if_statement.then_branch, context);
            },
            .IfExpression => |if_expression| {
                try self.validateNode(if_expression.condition, context);
                try self.validateNode(if_expression.then_block, context);
                try self.validateNode(if_expression.else_block, context);
            },
            .ExpressionStatement => |expression_statement| {
                try self.validateNode(expression_statement.expression, context);
            },
            .CallExpression => |call_expression| {
                try self.validateNode(call_expression.callee, context);
                for (call_expression.arguments) |*argument| {
                    try self.validateNode(argument, context);
                }
            },
            .BinaryExpression => |binary_expression| {
                try self.validateNode(binary_expression.left, context);
                try self.validateNode(binary_expression.right, context);
            },
            .UnaryExpression => |unary_expression| {
                try self.validateNode(unary_expression.operand, context);
            },
            .Block => |block| {
                for (block.statements) |*statement| {
                    try self.validateNode(statement, context);
                }
                if (block.result) |result_node| {
                    try self.validateNode(result_node, context);
                }
            },
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            => {},
        }
    }
};
