const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");

const ValidationContext = enum {
    Statement,
    Expression,
    FunctionBody,
};

const ExhaustivenessClass = enum {
    Boolean,
    IntegerOpen,
    Subjectless,
};

const TypeError = error{
    BlockMustProduceValue,
    BlockCannotProduceValue,
    TypeMismatch,
    NonExhaustiveMatch,
    DuplicateMatchArm,
};

pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    type_by_symbol_id: typing.TypeBySymbolId,
    type_by_node_id: typing.TypeByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .type_by_symbol_id = typing.TypeBySymbolId.init(allocator),
            .type_by_node_id = typing.TypeByNodeId.init(allocator),
        };
    }

    pub fn checkProgram(
        self: *@This(),
        resolved_program: symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypedProgram {
        self.type_by_symbol_id = typing.TypeBySymbolId.init(self.allocator);
        self.type_by_node_id = typing.TypeByNodeId.init(self.allocator);
        const context: ValidationContext = .Statement;

        try self.seedModuleLevelFunctionSignatures(&resolved_program);

        for (resolved_program.program.statements) |*statement| {
            _ = try self.checkNode(
                statement,
                &resolved_program,
                exit_behavior_by_node_id,
                context,
            );
        }

        return .{
            .resolved_program = resolved_program,
            .type_by_symbol_id = self.type_by_symbol_id,
            .type_by_node_id = self.type_by_node_id,
        };
    }

    fn seedModuleLevelFunctionSignatures(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        var iterator = resolved_program.symbol_table.entries.valueIterator();
        while (iterator.next()) |symbol| switch (symbol.*.kind) {
            .Function => |function_info| {
                switch (function_info.implementation) {
                    .UserDefined => {},
                    .BuiltinPrintInt => {
                        self.type_by_symbol_id.put(symbol.id, .Unit) catch unreachable;
                        const parameter_symbol_ids = resolved_program.parameter_symbol_ids_by_function_symbol_id.get(symbol.id) orelse unreachable;
                        for (parameter_symbol_ids) |parameter_symbol_id| {
                            self.type_by_symbol_id.put(parameter_symbol_id, .Integer) catch unreachable;
                        }
                    },
                    .BuiltinPrintString => {
                        self.type_by_symbol_id.put(symbol.id, .Unit) catch unreachable;
                        const parameter_symbol_ids = resolved_program.parameter_symbol_ids_by_function_symbol_id.get(symbol.id) orelse unreachable;
                        for (parameter_symbol_ids) |parameter_symbol_id| {
                            self.type_by_symbol_id.put(parameter_symbol_id, .String) catch unreachable;
                        }
                    },
                }
            },
            else => {},
        };

        for (resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .FunctionDefinition => |function_definition| {
                    const function_symbol_id = resolved_program.symbol_id_by_node_id.get(
                        statement.id,
                    ) orelse unreachable;
                    const function_return_type = try asType(function_definition.return_type_annotation);
                    self.type_by_symbol_id.put(function_symbol_id, function_return_type) catch unreachable;

                    const parameter_symbol_ids = resolved_program.parameter_symbol_ids_by_function_symbol_id.get(
                        function_symbol_id,
                    ) orelse unreachable;
                    for (function_definition.parameters, parameter_symbol_ids) |*parameter, symbol_id| {
                        const parameter_type = try asType(parameter.type_annotation);
                        self.type_by_symbol_id.put(symbol_id, parameter_type) catch unreachable;
                    }
                },
                else => {},
            }
        }
    }

    fn checkNode(
        self: *@This(),
        node: *const ast.Node,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.Type {
        switch (node.kind) {
            .Declaration => |declaration| return self.checkDeclarationNode(node.id, &declaration, resolved_program, exit_behavior_by_node_id),
            .FunctionDefinition => |function_definition| return self.checkFunctionDefinitionNode(node.id, &function_definition, resolved_program, exit_behavior_by_node_id),
            .Return => |return_statement| return self.checkReturnNode(node.id, &return_statement, resolved_program, exit_behavior_by_node_id),
            .Assignment => |assignment| return self.checkAssignmentNode(node.id, &assignment, resolved_program, exit_behavior_by_node_id),
            .Loop => |loop| return self.checkLoopNode(node.id, &loop, resolved_program, exit_behavior_by_node_id),
            .While => |while_statement| return self.checkWhileNode(node.id, &while_statement, resolved_program, exit_behavior_by_node_id),
            .Leave => return self.checkLeaveNode(node.id),
            .Continue => return self.checkContinueNode(node.id),
            .CallExpression => |call_expression| return self.checkCallExpressionNode(node.id, &call_expression, resolved_program, exit_behavior_by_node_id),
            .BinaryExpression => |binary_expression| return self.checkBinaryExpressionNode(node.id, &binary_expression, resolved_program, exit_behavior_by_node_id),
            .UnaryExpression => |unary_expression| return self.checkUnaryExpressionNode(node.id, &unary_expression, resolved_program, exit_behavior_by_node_id),
            .Block => |block| return self.checkBlockNode(node.id, &block, resolved_program, exit_behavior_by_node_id, context),
            .IntegerLiteral => return self.checkIntegerLiteralNode(node.id),
            .BooleanLiteral => return self.checkBooleanLiteralNode(node.id),
            .StringLiteral => return self.checkStringLiteralNode(node.id),
            .Identifier => return self.checkIdentifierNode(node.id, resolved_program),
            .IfStatement => |if_statement| return self.checkIfStatementNode(node.id, &if_statement, resolved_program, exit_behavior_by_node_id),
            .IfExpression => |if_expression| return self.checkIfExpressionNode(node.id, &if_expression, resolved_program, exit_behavior_by_node_id, context),
            .MatchExpression => |match_expression| return self.checkMatchExpressionNode(node.id, &match_expression, resolved_program, exit_behavior_by_node_id, context),
            .ExpressionStatement => |expression_statement| return self.checkExpressionStatementNode(node.id, &expression_statement, resolved_program, exit_behavior_by_node_id),
        }
    }

    fn checkDeclarationNode(
        self: *@This(),
        node_id: ast.NodeId,
        declaration: *const ast.Declaration,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const value_type = try self.checkNode(
            declaration.value,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const annotated_type = if (declaration.type_annotation) |type_annotation|
            try asType(type_annotation)
        else
            null;
        if (annotated_type) |annotated| {
            if (annotated != value_type) {
                std.debug.print(
                    "Type Error: Value declaration annotation does not match initializer type, expected {any}, got {any}\n",
                    .{ annotated, value_type },
                );
                return TypeError.TypeMismatch;
            }
        }

        const symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        self.type_by_symbol_id.put(symbol_id, value_type) catch unreachable;
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkFunctionDefinitionNode(
        self: *@This(),
        node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        try self.checkFunctionDefinition(
            node_id,
            function_definition,
            resolved_program,
            exit_behavior_by_node_id,
        );
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkReturnNode(
        self: *@This(),
        node_id: ast.NodeId,
        return_statement: *const ast.Return,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        if (return_statement.value) |return_value| {
            _ = try self.checkNode(
                return_value,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
        }

        return self.recordNodeType(node_id, .Unit);
    }

    fn checkAssignmentNode(
        self: *@This(),
        node_id: ast.NodeId,
        assignment: *const ast.Assignment,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const value_type = try self.checkNode(
            assignment.value,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
        if (symbol_type != value_type) {
            std.debug.print(
                "Type Error: Cannot assign value of type {any} to symbol of type {any}\n",
                .{ value_type, symbol_type },
            );
            return TypeError.TypeMismatch;
        }

        return self.recordNodeType(node_id, .Unit);
    }

    fn checkLoopNode(
        self: *@This(),
        node_id: ast.NodeId,
        loop: *const ast.Loop,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        _ = try self.checkNode(
            loop.body_block,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkWhileNode(
        self: *@This(),
        node_id: ast.NodeId,
        while_statement: *const ast.While,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const while_condition_type = try self.checkNode(
            while_statement.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (while_condition_type != .Boolean) {
            std.debug.print(
                "Type Error: While condition must be of type boolean, got {any}\n",
                .{while_condition_type},
            );
            return TypeError.TypeMismatch;
        }

        if (while_statement.update) |update| {
            _ = try self.checkNode(
                update,
                resolved_program,
                exit_behavior_by_node_id,
                .Statement,
            );
        }

        _ = try self.checkNode(
            while_statement.body_block,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkLeaveNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.Type {
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkContinueNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.Type {
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkCallExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        call_expression: *const ast.CallExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        switch (call_expression.callee.kind) {
            .Identifier => {
                const callee_symbol_id = resolved_program.symbol_id_by_node_id.get(
                    call_expression.callee.id,
                ) orelse unreachable;
                const parameter_symbol_ids = resolved_program.parameter_symbol_ids_by_function_symbol_id.get(
                    callee_symbol_id,
                ) orelse unreachable;
                if (call_expression.arguments.len != parameter_symbol_ids.len) {
                    std.debug.print(
                        "Type Error: Function expected {any} arguments, got {any}\n",
                        .{ parameter_symbol_ids.len, call_expression.arguments.len },
                    );
                    return TypeError.TypeMismatch;
                }

                for (call_expression.arguments, parameter_symbol_ids) |*argument, parameter_symbol_id| {
                    const argument_type = try self.checkNode(
                        argument,
                        resolved_program,
                        exit_behavior_by_node_id,
                        .Expression,
                    );
                    const parameter_type = self.type_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
                    if (argument_type != parameter_type) {
                        std.debug.print(
                            "Type Error: Function parameter expected type {any}, got {any}\n",
                            .{ parameter_type, argument_type },
                        );
                        return TypeError.TypeMismatch;
                    }
                }

                const function_return_type = self.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                return self.recordNodeType(node_id, function_return_type);
            },
            else => return TypeError.TypeMismatch,
        }
    }

    fn checkBinaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const left_expression_type = try self.checkNode(
            binary_expression.left,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const right_expression_type = try self.checkNode(
            binary_expression.right,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (typing.binary_operator_rules_by_type.get(left_expression_type)) |rules_for_left_type| {
            if (rules_for_left_type.get(binary_expression.operator)) |operator_rule| {
                if (operator_rule.argument_type != right_expression_type) {
                    std.debug.print(
                        "Type Error: Binary operator {any} expected right operand of type {any}, got {any}\n",
                        .{ binary_expression.operator, operator_rule.argument_type, right_expression_type },
                    );
                    return TypeError.TypeMismatch;
                }
                return self.recordNodeType(node_id, operator_rule.return_type);
            } else {
                std.debug.print(
                    "Type Error: Binary operator {any} is not supported for left operand type {any}\n",
                    .{ binary_expression.operator, left_expression_type },
                );
                return TypeError.TypeMismatch;
            }
        } else {
            std.debug.print(
                "Type Error: No binary operator rules exist for left operand type {any}\n",
                .{left_expression_type},
            );
            return TypeError.TypeMismatch;
        }
    }

    fn checkUnaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        unary_expression: *const ast.UnaryExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const operand_type = try self.checkNode(
            unary_expression.operand,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (typing.unary_operator_rules_by_type.get(operand_type)) |rules_for_operand_type| {
            if (rules_for_operand_type.get(unary_expression.operator)) |operator_rule| {
                return self.recordNodeType(node_id, operator_rule.return_type);
            } else {
                std.debug.print(
                    "Type Error: Unary operator {any} is not supported for operand type {any}\n",
                    .{ unary_expression.operator, operand_type },
                );
                return TypeError.TypeMismatch;
            }
        } else {
            std.debug.print(
                "Type Error: No unary operator rules exist for operand type {any}\n",
                .{operand_type},
            );
            return TypeError.TypeMismatch;
        }
    }

    fn checkBlockNode(
        self: *@This(),
        node_id: ast.NodeId,
        block: *const ast.Block,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.Type {
        if (context == .Expression and block.result == null) {
            std.debug.print("Type Error: Block must produce a value in this context\n", .{});
            return TypeError.BlockMustProduceValue;
        }
        if (context == .Statement and block.result != null) {
            std.debug.print("Type Error: Block cannot have a trailing expression in statement context\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        for (block.statements) |*statement| {
            _ = try self.checkNode(
                statement,
                resolved_program,
                exit_behavior_by_node_id,
                .Statement,
            );
        }
        if (block.result) |result_node| {
            const result_type = try self.checkNode(
                result_node,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
            return self.recordNodeType(node_id, result_type);
        }

        return self.recordNodeType(node_id, .Unit);
    }

    fn checkIntegerLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.Type {
        return self.recordNodeType(node_id, .Integer);
    }

    fn checkBooleanLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.Type {
        return self.recordNodeType(node_id, .Boolean);
    }

    fn checkStringLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.Type {
        return self.recordNodeType(node_id, .String);
    }

    fn checkIdentifierNode(
        self: *@This(),
        node_id: ast.NodeId,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!typing.Type {
        const symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
        return self.recordNodeType(node_id, symbol_type);
    }

    fn checkIfStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_statement: *const ast.IfStatement,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const if_condition_type = try self.checkNode(
            if_statement.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (if_condition_type != .Boolean) {
            std.debug.print(
                "Type Error: If condition must be of type boolean, got {any}\n",
                .{if_condition_type},
            );
            return TypeError.TypeMismatch;
        }

        _ = try self.checkNode(
            if_statement.then_branch,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, .Unit);
    }

    fn checkIfExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_expression: *const ast.IfExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.Type {
        const if_condition_type = try self.checkNode(
            if_expression.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (if_condition_type != .Boolean) {
            std.debug.print(
                "Type Error: If condition must be of type boolean, got {any}\n",
                .{if_condition_type},
            );
            return TypeError.TypeMismatch;
        }

        const then_block_type = try self.checkNode(
            if_expression.then_block,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        const else_block_type = try self.checkNode(
            if_expression.else_block,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        if (then_block_type != else_block_type) {
            std.debug.print(
                "Type Error: Then and else blocks of an if expression must have the same type, got then: {any}, else: {any}\n",
                .{ then_block_type, else_block_type },
            );
            return TypeError.TypeMismatch;
        }

        return self.recordNodeType(node_id, then_block_type);
    }

    fn checkMatchExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        match_expression: *const ast.MatchExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.Type {
        const match_type = try self.checkMatchExpression(
            match_expression,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        return self.recordNodeType(node_id, match_type);
    }

    fn checkExpressionStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        expression_statement: *const ast.ExpressionStatement,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.Type {
        const expression_type = try self.checkNode(
            expression_statement.expression,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        if (expression_type != .Unit) {
            std.debug.print("Type Error: Expression statement must evaluate to unit\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        return self.recordNodeType(node_id, .Unit);
    }

    fn checkFunctionDefinitionReturnValue(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!void {
        const symbol_id = resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const function_return_type = try asType(function_definition.return_type_annotation);

        const body_expression_type = try self.checkNode(
            function_definition.body_expression,
            resolved_program,
            exit_behavior_by_node_id,
            .FunctionBody,
        );
        try self.checkReturnStatementsMatchType(
            function_definition.body_expression,
            function_return_type,
            resolved_program,
        );
        self.type_by_symbol_id.put(symbol_id, function_return_type) catch unreachable;

        const body_exit_behavior = exit_behavior_by_node_id.get(
            function_definition.body_expression.id,
        ) orelse unreachable;
        switch (body_exit_behavior) {
            // This is okay, all control flow paths return and we validated that all return statements return the correct type
            .Terminates => {},
            .FallsThroughWithoutValue => {
                if (function_return_type != .Unit) {
                    std.debug.print(
                        "Type Error: Function with non-unit return type {any} has control flow path that falls through without returning a value\n",
                        .{function_return_type},
                    );
                    return TypeError.TypeMismatch;
                }
            },
            .FallsThroughWithValue => {
                if (function_return_type != body_expression_type) {
                    std.debug.print(
                        "Type Error: Function with return type {any} has control flow path that falls through with value of type {any}\n",
                        .{ function_return_type, body_expression_type },
                    );
                    return TypeError.TypeMismatch;
                }
            },
        }
    }

    fn checkFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!void {
        const function_symbol_id = resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const parameter_symbol_ids = resolved_program.parameter_symbol_ids_by_function_symbol_id.get(
            function_symbol_id,
        ).?;
        for (function_definition.parameters, parameter_symbol_ids) |*parameter, symbol_id| {
            const parameter_type = try asType(parameter.type_annotation);
            self.type_by_symbol_id.put(symbol_id, parameter_type) catch unreachable;
        }

        try self.checkFunctionDefinitionReturnValue(
            function_node_id,
            function_definition,
            resolved_program,
            exit_behavior_by_node_id,
        );
    }

    fn checkReturnStatementsMatchType(
        self: *@This(),
        node: *const ast.Node,
        function_return_type: typing.Type,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        switch (node.kind) {
            .Return => |return_statement| {
                if (return_statement.value) |return_value| {
                    const return_value_type = self.type_by_node_id.get(return_value.id).?;
                    if (return_value_type != function_return_type) {
                        std.debug.print(
                            "Type Error: Return statement in function with return type {any} has return value of type {any}\n",
                            .{ function_return_type, return_value_type },
                        );
                        return TypeError.TypeMismatch;
                    }
                } else {
                    if (function_return_type != .Unit) {
                        std.debug.print(
                            "Type Error: Return statement with no value in function with non-unit return type {any}\n",
                            .{function_return_type},
                        );
                        return TypeError.TypeMismatch;
                    }
                }
            },
            .IfStatement => |if_statement| {
                try self.checkReturnStatementsMatchType(if_statement.then_branch, function_return_type, resolved_program);
            },
            .IfExpression => |if_expression| {
                try self.checkReturnStatementsMatchType(if_expression.then_block, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(if_expression.else_block, function_return_type, resolved_program);
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    try self.checkReturnStatementsMatchType(subject, function_return_type, resolved_program);
                }
                for (match_expression.arms) |arm| {
                    try self.checkReturnStatementsMatchType(arm.pattern_or_condition, function_return_type, resolved_program);
                    try self.checkReturnStatementsMatchType(arm.body, function_return_type, resolved_program);
                }
                if (match_expression.else_arm) |else_arm| {
                    try self.checkReturnStatementsMatchType(else_arm, function_return_type, resolved_program);
                }
            },
            .Block => |block| {
                for (block.statements) |*statement| {
                    try self.checkReturnStatementsMatchType(statement, function_return_type, resolved_program);
                }
                if (block.result) |result_node| {
                    try self.checkReturnStatementsMatchType(result_node, function_return_type, resolved_program);
                }
            },
            .Loop => |loop| {
                try self.checkReturnStatementsMatchType(loop.body_block, function_return_type, resolved_program);
            },
            .While => |while_statement| {
                try self.checkReturnStatementsMatchType(while_statement.body_block, function_return_type, resolved_program);
            },
            .CallExpression => |call_expression| {
                try self.checkReturnStatementsMatchType(call_expression.callee, function_return_type, resolved_program);
                for (call_expression.arguments) |*argument| {
                    try self.checkReturnStatementsMatchType(argument, function_return_type, resolved_program);
                }
            },
            .Assignment => |assignment| {
                try self.checkReturnStatementsMatchType(assignment.value, function_return_type, resolved_program);
            },
            .Declaration => |declaration| {
                try self.checkReturnStatementsMatchType(declaration.value, function_return_type, resolved_program);
            },
            .ExpressionStatement => |expression_statement| {
                try self.checkReturnStatementsMatchType(expression_statement.expression, function_return_type, resolved_program);
            },
            .BinaryExpression => |binary_expression| {
                try self.checkReturnStatementsMatchType(binary_expression.left, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(binary_expression.right, function_return_type, resolved_program);
            },
            .UnaryExpression => |unary_expression| {
                try self.checkReturnStatementsMatchType(unary_expression.operand, function_return_type, resolved_program);
            },
            .FunctionDefinition => unreachable,
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .Leave,
            .Continue,
            => {},
        }
    }

    fn asType(typeAnnotation: ast.TypeAnnotation) !typing.Type {
        const type_name = typeAnnotation.name_token.kind.Identifier;
        if (std.mem.eql(u8, type_name, "boolean")) {
            return .Boolean;
        } else if (std.mem.eql(u8, type_name, "unit")) {
            return .Unit;
        } else if (std.mem.eql(u8, type_name, "int")) {
            return .Integer;
        } else if (std.mem.eql(u8, type_name, "string")) {
            return .String;
        } else {
            std.debug.print("Type Error: Unknown type annotation: {s}\n", .{type_name});
            return TypeError.TypeMismatch;
        }
    }

    fn checkMatchExpression(
        self: *@This(),
        match_expression: *const ast.MatchExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.Type {
        const exhaustiveness_class: ExhaustivenessClass = if (match_expression.subject) |subject| class: {
            const subject_type = try self.checkNode(
                subject,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
            break :class switch (subject_type) {
                .Boolean => .Boolean,
                .Integer => .IntegerOpen,
                else => {
                    std.debug.print("Type Error: Match subject must be boolean or integer in v1, got {any}\n", .{subject_type});
                    return TypeError.TypeMismatch;
                },
            };
        } else .Subjectless;

        var saw_true = false;
        var saw_false = false;
        var integer_patterns = std.AutoHashMap(i64, void).init(self.allocator);
        defer integer_patterns.deinit();

        var arm_result_type: ?typing.Type = null;
        for (match_expression.arms) |arm| {
            switch (exhaustiveness_class) {
                .Subjectless => {
                    const condition_type = try self.checkNode(
                        arm.pattern_or_condition,
                        resolved_program,
                        exit_behavior_by_node_id,
                        .Expression,
                    );
                    if (condition_type != .Boolean) {
                        std.debug.print("Type Error: Subjectless match arm condition must be boolean, got {any}\n", .{condition_type});
                        return TypeError.TypeMismatch;
                    }
                },
                .Boolean => switch (arm.pattern_or_condition.kind) {
                    .BooleanLiteral => |token| {
                        if (token.kind.BooleanLiteral) {
                            if (saw_true) return TypeError.DuplicateMatchArm;
                            saw_true = true;
                        } else {
                            if (saw_false) return TypeError.DuplicateMatchArm;
                            saw_false = true;
                        }
                        self.type_by_node_id.put(arm.pattern_or_condition.id, .Boolean) catch unreachable;
                    },
                    else => {
                        std.debug.print("Type Error: Boolean match arms must use boolean literals in v1\n", .{});
                        return TypeError.TypeMismatch;
                    },
                },
                .IntegerOpen => switch (arm.pattern_or_condition.kind) {
                    .IntegerLiteral => |token| {
                        _ = try self.checkNode(
                            arm.pattern_or_condition,
                            resolved_program,
                            exit_behavior_by_node_id,
                            .Expression,
                        );
                        const value = token.kind.IntLiteral;
                        if (integer_patterns.contains(value)) {
                            return TypeError.DuplicateMatchArm;
                        }
                        integer_patterns.put(value, {}) catch unreachable;
                    },
                    else => {
                        const pattern_type = try self.checkNode(
                            arm.pattern_or_condition,
                            resolved_program,
                            exit_behavior_by_node_id,
                            .Expression,
                        );
                        if (pattern_type != .Integer) {
                            std.debug.print("Type Error: Integer match arms must be integer expressions in v1\n", .{});
                            return TypeError.TypeMismatch;
                        }
                    },
                },
            }

            const body_type = try self.checkNode(
                arm.body,
                resolved_program,
                exit_behavior_by_node_id,
                context,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != body_type) {
                    std.debug.print(
                        "Type Error: Match arms must all produce the same type, expected {any}, got {any}\n",
                        .{ expected_type, body_type },
                    );
                    return TypeError.TypeMismatch;
                }
            } else {
                arm_result_type = body_type;
            }
        }

        if (match_expression.else_arm) |else_arm| {
            const else_type = try self.checkNode(
                else_arm,
                resolved_program,
                exit_behavior_by_node_id,
                context,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != else_type) {
                    std.debug.print(
                        "Type Error: Match else arm must produce the same type as other arms, expected {any}, got {any}\n",
                        .{ expected_type, else_type },
                    );
                    return TypeError.TypeMismatch;
                }
            } else {
                arm_result_type = else_type;
            }
        }

        const is_exhaustive = switch (exhaustiveness_class) {
            .Subjectless => match_expression.else_arm != null,
            .Boolean => (saw_true and saw_false) or match_expression.else_arm != null,
            .IntegerOpen => match_expression.else_arm != null,
        };
        if (!is_exhaustive) {
            std.debug.print("Type Error: Match expression is not exhaustive in v1\n", .{});
            return TypeError.NonExhaustiveMatch;
        }

        const result_type = arm_result_type orelse .Unit;
        if (context == .Statement and result_type != .Unit) {
            std.debug.print("Type Error: Match expression used as statement must evaluate to unit\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        return result_type;
    }

    fn recordNodeType(
        self: *@This(),
        node_id: ast.NodeId,
        node_type: typing.Type,
    ) typing.Type {
        self.type_by_node_id.put(node_id, node_type) catch unreachable;
        return node_type;
    }
};
