const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

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
    symbol_type_map: typing.SymbolTypeMap,
    node_type_map: typing.NodeTypeMap,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_type_map = typing.SymbolTypeMap.init(allocator),
            .node_type_map = typing.NodeTypeMap.init(allocator),
        };
    }

    pub fn check(
        self: *@This(),
        resolved_program: symbols.ResolvedProgram,
    ) !typing.TypedProgram {
        self.symbol_type_map = typing.SymbolTypeMap.init(self.allocator);
        self.node_type_map = typing.NodeTypeMap.init(self.allocator);
        var context = ValidationContext{
            .requires_value = false,
        };

        for (resolved_program.program.statements) |*statement| {
            try self.checkNode(
                statement,
                &resolved_program,
                &context,
            );
        }

        return .{
            .resolved_program = resolved_program,
            .symbol_type_map = self.symbol_type_map,
            .node_type_map = self.node_type_map,
        };
    }

    fn checkNode(
        self: *@This(),
        node: *const ast.Node,
        resolved_program: *const symbols.ResolvedProgram,
        context: *const ValidationContext,
    ) !void {
        switch (node.kind) {
            .ValueDeclaration => |value_declaration| {
                try self.checkNode(
                    value_declaration.value,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const value_type = self.node_type_map.get(value_declaration.value.id).?;
                const annotated_type = if (value_declaration.type_annotation) |type_annotation|
                    try asType(type_annotation)
                else
                    null;
                if (annotated_type) |annotated| {
                    if (annotated != value_type) {
                        std.debug.print("Type Error: TODO\n", .{});
                        return TypeError.TypeMismatch;
                    }
                }
                const symbol_id = resolved_program.name_resolution_map.get(node.id).?;
                try self.symbol_type_map.put(symbol_id, value_type);
                try self.node_type_map.put(node.id, .Unit);
            },
            .BinaryExpression => |binaryExpression| {
                try self.checkNode(
                    binaryExpression.left,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                try self.checkNode(
                    binaryExpression.right,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );

                const left_expression_type = self.node_type_map.get(binaryExpression.left.id).?;
                const right_expression_type = self.node_type_map.get(binaryExpression.right.id).?;
                if (typing.binary_operator_rules_by_type.get(left_expression_type)) |rules_for_left_type| {
                    if (rules_for_left_type.get(binaryExpression.operator)) |operator_rule| {
                        if (operator_rule.argument_type != right_expression_type) {
                            std.debug.print("Type Error: TODO\n", .{});
                            return TypeError.TypeMismatch;
                        }
                        try self.node_type_map.put(node.id, operator_rule.return_type);
                    } else {
                        std.debug.print("Type Error: TODO\n", .{});
                        return TypeError.TypeMismatch;
                    }
                } else {
                    std.debug.print("Type Error: TODO\n", .{});
                    return TypeError.TypeMismatch;
                }
            },
            .UnaryExpression => |unaryExpression| {
                try self.checkNode(
                    unaryExpression.operand,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const operand_type = self.node_type_map.get(unaryExpression.operand.id).?;
                if (typing.unary_operator_rules_by_type.get(operand_type)) |rules_for_operand_type| {
                    if (rules_for_operand_type.get(unaryExpression.operator)) |operator_rule| {
                        try self.node_type_map.put(node.id, operator_rule.return_type);
                    } else {
                        std.debug.print("Type Error: TODO\n", .{});
                        return TypeError.TypeMismatch;
                    }
                } else {
                    std.debug.print("Type Error: TODO\n", .{});
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
                        &ValidationContext{ .requires_value = false },
                    );
                }
                if (block.result) |result_node| {
                    try self.checkNode(
                        result_node,
                        resolved_program,
                        &ValidationContext{ .requires_value = true },
                    );
                    const result_type = self.node_type_map.get(result_node.id).?;
                    try self.node_type_map.put(node.id, result_type);
                }
            },
            .IntegerLiteral => {
                try self.node_type_map.put(node.id, .Integer);
            },
            .BooleanLiteral => {
                try self.node_type_map.put(node.id, .Boolean);
            },
            .Identifier => {
                const symbol_id = resolved_program.name_resolution_map.get(node.id).?;
                const symbol_type = self.symbol_type_map.get(symbol_id).?;
                try self.node_type_map.put(node.id, symbol_type);
            },
            .IfStatement => |if_statement| {
                try self.checkNode(
                    if_statement.condition,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const if_condition_type = self.node_type_map.get(if_statement.condition.id).?;
                if (if_condition_type != .Boolean) {
                    std.debug.print("Type Error: If condition must be of type boolean, got {any}\n", .{if_condition_type});
                    return TypeError.TypeMismatch;
                }

                try self.checkNode(
                    if_statement.then_branch,
                    resolved_program,
                    &ValidationContext{ .requires_value = false },
                );

                if (if_statement.else_branch) |else_branch| {
                    try self.checkNode(
                        else_branch.else_block,
                        resolved_program,
                        &ValidationContext{ .requires_value = false },
                    );
                }
            },
            .IfExpression => |if_expression| {
                try self.checkNode(
                    if_expression.condition,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const if_condition_type = self.node_type_map.get(if_expression.condition.id).?;
                if (if_condition_type != .Boolean) {
                    std.debug.print("Type Error: If condition must be of type boolean, got {any}\n", .{if_condition_type});
                    return TypeError.TypeMismatch;
                }

                try self.checkNode(
                    if_expression.then_block,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const then_block_type = self.node_type_map.get(if_expression.then_block.id).?;

                try self.checkNode(
                    if_expression.else_block,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                const else_block_type = self.node_type_map.get(if_expression.else_block.id).?;

                if (then_block_type != else_block_type) {
                    std.debug.print("Type Error: Then and else blocks of an if expression must have the same type, got then: {any}, else: {any}\n", .{ then_block_type, else_block_type });
                    return TypeError.TypeMismatch;
                }

                try self.node_type_map.put(node.id, then_block_type);
            },
            .ExpressionStatement => |expression_statement| {
                try self.checkNode(
                    expression_statement.expression,
                    resolved_program,
                    &ValidationContext{ .requires_value = true },
                );
                try self.node_type_map.put(node.id, .Unit);
            },
        }
    }

    fn asType(typeAnnotation: ast.TypeAnnotation) !typing.Type {
        const typeName = typeAnnotation.name_token.kind.Identifier;
        if (std.mem.eql(u8, typeName, "boolean")) {
            return .Boolean;
        } else if (std.mem.eql(u8, typeName, "int")) {
            return .Integer;
        } else {
            std.debug.print("Type Error: Unknown type annotation: {s}\n", .{typeName});
            return TypeError.TypeMismatch;
        }
    }
};
