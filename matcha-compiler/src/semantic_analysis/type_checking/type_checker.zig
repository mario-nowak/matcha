const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");

const ValidationContext = struct {
    requires_value: bool,
};

const TypeError = error{
    BlockMustProduceValue,
    BlockCannotProduceValue,
    TypeMismatch,
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
        var context = ValidationContext{
            .requires_value = false,
        };

        try self.seedModuleLevelFunctionSignatures(&resolved_program);

        for (resolved_program.program.statements) |*statement| {
            try self.checkNode(
                statement,
                &resolved_program,
                exit_behavior_by_node_id,
                &context,
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
        context: *const ValidationContext,
    ) TypeError!void {
        switch (node.kind) {
            .Declaration => |value_declaration| {
                try self.checkNode(
                    value_declaration.value,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const value_type = self.type_by_node_id.get(value_declaration.value.id).?;
                const annotated_type = if (value_declaration.type_annotation) |type_annotation|
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
                const symbol_id = resolved_program.symbol_id_by_node_id.get(node.id).?;
                self.type_by_symbol_id.put(symbol_id, value_type) catch unreachable;
                self.type_by_node_id.put(node.id, .Unit) catch unreachable;
            },
            .FunctionDefinition => |function_definition| {
                try self.checkFunctionDefinition(
                    node.id,
                    &function_definition,
                    resolved_program,
                    exit_behavior_by_node_id,
                );
                self.type_by_node_id.put(node.id, .Unit) catch unreachable;
            },
            .Return => |return_statement| {
                if (return_statement.value) |return_value| {
                    try self.checkNode(
                        return_value,
                        resolved_program,
                        exit_behavior_by_node_id,
                        &ValidationContext{ .requires_value = true },
                    );
                }
            },
            .Assignment => |assignment| {
                try self.checkNode(
                    assignment.value,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const value_type = self.type_by_node_id.get(assignment.value.id).?;
                const symbol_id = resolved_program.symbol_id_by_node_id.get(node.id).?;
                const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
                if (symbol_type != value_type) {
                    std.debug.print(
                        "Type Error: Cannot assign value of type {any} to symbol of type {any}\n",
                        .{ value_type, symbol_type },
                    );
                    return TypeError.TypeMismatch;
                }
                self.type_by_node_id.put(node.id, .Unit) catch unreachable;
            },
            .Loop => |loop| {
                try self.checkNode(
                    loop.body_block,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = false },
                );
            },
            .While => |while_statement| {
                try self.checkNode(
                    while_statement.condition,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const while_condition_type = self.type_by_node_id.get(while_statement.condition.id).?;
                if (while_condition_type != .Boolean) {
                    std.debug.print("Type Error: While condition must be of type boolean, got {any}\n", .{while_condition_type});
                    return TypeError.TypeMismatch;
                }
                if (while_statement.update) |update| {
                    try self.checkNode(
                        update,
                        resolved_program,
                        exit_behavior_by_node_id,
                        &ValidationContext{ .requires_value = false },
                    );
                }
                try self.checkNode(
                    while_statement.body_block,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = false },
                );
            },
            .Leave => {},
            .Continue => {},
            .CallExpression => |call_expression| {
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
                            try self.checkNode(
                                argument,
                                resolved_program,
                                exit_behavior_by_node_id,
                                &ValidationContext{ .requires_value = true },
                            );
                            const argument_type = self.type_by_node_id.get(argument.id) orelse unreachable;
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

                        self.type_by_node_id.put(node.id, function_return_type) catch unreachable;
                    },
                    else => return TypeError.TypeMismatch,
                }
            },
            .BinaryExpression => |binaryExpression| {
                try self.checkNode(
                    binaryExpression.left,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                try self.checkNode(
                    binaryExpression.right,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );

                const left_expression_type = self.type_by_node_id.get(binaryExpression.left.id).?;
                const right_expression_type = self.type_by_node_id.get(binaryExpression.right.id).?;
                if (typing.binary_operator_rules_by_type.get(left_expression_type)) |rules_for_left_type| {
                    if (rules_for_left_type.get(binaryExpression.operator)) |operator_rule| {
                        if (operator_rule.argument_type != right_expression_type) {
                            std.debug.print(
                                "Type Error: Binary operator {any} expected right operand of type {any}, got {any}\n",
                                .{ binaryExpression.operator, operator_rule.argument_type, right_expression_type },
                            );
                            return TypeError.TypeMismatch;
                        }
                        self.type_by_node_id.put(node.id, operator_rule.return_type) catch unreachable;
                    } else {
                        std.debug.print(
                            "Type Error: Binary operator {any} is not supported for left operand type {any}\n",
                            .{ binaryExpression.operator, left_expression_type },
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
            },
            .UnaryExpression => |unaryExpression| {
                try self.checkNode(
                    unaryExpression.operand,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const operand_type = self.type_by_node_id.get(unaryExpression.operand.id).?;
                if (typing.unary_operator_rules_by_type.get(operand_type)) |rules_for_operand_type| {
                    if (rules_for_operand_type.get(unaryExpression.operator)) |operator_rule| {
                        self.type_by_node_id.put(node.id, operator_rule.return_type) catch unreachable;
                    } else {
                        std.debug.print(
                            "Type Error: Unary operator {any} is not supported for operand type {any}\n",
                            .{ unaryExpression.operator, operand_type },
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
            },
            .Block => |block| {
                if (context.requires_value and block.result == null) {
                    std.debug.print("Type Error: Block must produce a value in this context\n", .{});
                    return TypeError.BlockMustProduceValue;
                }
                if (!context.requires_value and block.result != null) {
                    std.debug.print("Type Error: Block cannot have a trailing expression in statement context\n", .{});
                    return TypeError.BlockCannotProduceValue;
                }

                for (block.statements) |*statement| {
                    try self.checkNode(
                        statement,
                        resolved_program,
                        exit_behavior_by_node_id,
                        &ValidationContext{ .requires_value = false },
                    );
                }
                if (block.result) |result_node| {
                    try self.checkNode(
                        result_node,
                        resolved_program,
                        exit_behavior_by_node_id,
                        &ValidationContext{ .requires_value = true },
                    );
                    const result_type = self.type_by_node_id.get(result_node.id).?;
                    self.type_by_node_id.put(node.id, result_type) catch unreachable;
                } else {
                    self.type_by_node_id.put(node.id, .Unit) catch unreachable;
                }
            },
            .IntegerLiteral => {
                self.type_by_node_id.put(node.id, .Integer) catch unreachable;
            },
            .BooleanLiteral => {
                self.type_by_node_id.put(node.id, .Boolean) catch unreachable;
            },
            .Identifier => {
                const symbol_id = resolved_program.symbol_id_by_node_id.get(node.id).?;
                const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
                self.type_by_node_id.put(node.id, symbol_type) catch unreachable;
            },
            .IfStatement => |if_statement| {
                try self.checkNode(
                    if_statement.condition,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const if_condition_type = self.type_by_node_id.get(if_statement.condition.id).?;
                if (if_condition_type != .Boolean) {
                    std.debug.print("Type Error: If condition must be of type boolean, got {any}\n", .{if_condition_type});
                    return TypeError.TypeMismatch;
                }

                try self.checkNode(
                    if_statement.then_branch,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = false },
                );
                self.type_by_node_id.put(node.id, .Unit) catch unreachable;
            },
            .IfExpression => |if_expression| {
                try self.checkNode(
                    if_expression.condition,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = true },
                );
                const if_condition_type = self.type_by_node_id.get(if_expression.condition.id).?;
                if (if_condition_type != .Boolean) {
                    std.debug.print("Type Error: If condition must be of type boolean, got {any}\n", .{if_condition_type});
                    return TypeError.TypeMismatch;
                }

                try self.checkNode(
                    if_expression.then_block,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = context.requires_value },
                );
                const then_block_type = self.type_by_node_id.get(if_expression.then_block.id).?;

                try self.checkNode(
                    if_expression.else_block,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = context.requires_value },
                );
                const else_block_type = self.type_by_node_id.get(if_expression.else_block.id).?;

                if (then_block_type != else_block_type) {
                    std.debug.print(
                        "Type Error: Then and else blocks of an if expression must have the same type, got then: {any}, else: {any}\n",
                        .{ then_block_type, else_block_type },
                    );
                    return TypeError.TypeMismatch;
                }

                self.type_by_node_id.put(node.id, then_block_type) catch unreachable;
            },
            .ExpressionStatement => |expression_statement| {
                try self.checkNode(
                    expression_statement.expression,
                    resolved_program,
                    exit_behavior_by_node_id,
                    &ValidationContext{ .requires_value = false },
                );
                self.type_by_node_id.put(node.id, .Unit) catch unreachable;
            },
        }
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

        try self.checkNode(
            function_definition.body_expression,
            resolved_program,
            exit_behavior_by_node_id,
            &ValidationContext{ .requires_value = false },
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
        const body_expression_type = self.type_by_node_id.get(
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
        } else {
            std.debug.print("Type Error: Unknown type annotation: {s}\n", .{type_name});
            return TypeError.TypeMismatch;
        }
    }
};
