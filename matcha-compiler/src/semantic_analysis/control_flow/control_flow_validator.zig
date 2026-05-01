pub const std = @import("std");
pub const ast = @import("ast");
const type_expressions = @import("type_expressions");

pub const ControlFlowValidationError = error{
    LeaveUsedOutsideOfLoop,
    ContinueUsedOutsideOfLoop,
    ItemDefinitionInNonTopLevel,
    NotAllPathsReturnValue,
    ReturnWithoutValueInNonUnitFunction,
    ReturnUsedOutsideOfFunction,
};

pub const ExitBehavior = enum {
    FallsThroughWithValue,
    FallsThroughWithoutValue,
    Terminates,
};

pub const ExitBehaviorByNodeId = std.AutoHashMap(ast.NodeId, ExitBehavior);

pub const ControlFlowValidationContext = struct {
    loop_depth: u32 = 0,
    scope_depth: u32 = 0,
    in_function: bool = false,
};

pub const ControlFlowValidator = struct {
    exit_behavior_by_node_id: ExitBehaviorByNodeId,

    pub fn init(
        allocator: std.mem.Allocator,
    ) @This() {
        return .{
            .exit_behavior_by_node_id = ExitBehaviorByNodeId.init(allocator),
        };
    }

    pub fn validateProgram(
        self: *@This(),
        program: *const ast.Program,
    ) ControlFlowValidationError!ExitBehaviorByNodeId {
        const context = ControlFlowValidationContext{};
        for (program.statements) |*statement| {
            try self.validateNode(statement, &context);
        }

        return self.exit_behavior_by_node_id;
    }

    fn validateNode(
        self: *@This(),
        node: *const ast.Node,
        context: *const ControlFlowValidationContext,
    ) ControlFlowValidationError!void {
        switch (node.kind) {
            .Declaration => |declaration| {
                try self.validateNode(declaration.value, context);
            },
            .ItemDefinition => |item_definition| {
                if (context.scope_depth > 0) {
                    std.debug.print("Semantic Error: Item definitions are only allowed at the top level\n", .{});
                    return ControlFlowValidationError.ItemDefinitionInNonTopLevel;
                }
                switch (item_definition.item) {
                    .Function => |function_definition| {
                        const function_context = ControlFlowValidationContext{
                            .loop_depth = 0,
                            .scope_depth = 0,
                            .in_function = true,
                        };
                        try self.validateNode(function_definition.body_expression, &function_context);
                        try self.validateFunctionReturnsValue(&function_definition);
                    },
                    .Structure => {},
                }
            },
            .Return => |return_statement| {
                if (!context.in_function) {
                    std.debug.print("Semantic Error: Return statements are only allowed inside functions\n", .{});
                    return ControlFlowValidationError.ReturnUsedOutsideOfFunction;
                }
                if (return_statement.value) |expression| {
                    try self.validateNode(expression, context);
                }
            },
            .Assignment => |assignment| {
                try self.validateNode(assignment.target, context);
                try self.validateNode(assignment.value, context);
            },
            .Loop => |loop| {
                const loop_context = ControlFlowValidationContext{
                    .loop_depth = context.loop_depth + 1,
                    .scope_depth = context.scope_depth,
                    .in_function = context.in_function,
                };
                try self.validateNode(loop.body_block, &loop_context);
            },
            .StructureConstruction => |structure_construction| {
                for (structure_construction.fields) |field| {
                    try self.validateNode(field.value, context);
                }
            },
            .While => |while_statement| {
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
            .MatchExpression => |match_expression| {
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
            .MemberAccess => |member_access| {
                try self.validateNode(member_access.base, context);
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    try self.validateNode(element, context);
                }
            },
            .IndexAccess => |index_access| {
                try self.validateNode(index_access.base, context);
                try self.validateNode(index_access.index, context);
            },
            .Block => |block| {
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
            },
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            => {},
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
        switch (node.kind) {
            .Return => |_| {
                self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                return .Terminates;
            },
            .Block => |block| {
                for (block.statements) |*statement| {
                    const result = try self.validateTerminatesWithValue(statement);
                    if (result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }

                if (block.result) |result_node| {
                    self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                    return self.validateTerminatesWithValue(result_node);
                } else {
                    self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                    return .FallsThroughWithoutValue;
                }
            },
            .Declaration => |declaration| {
                const result = try self.validateTerminatesWithValue(declaration.value);
                self.exit_behavior_by_node_id.put(declaration.value.id, result) catch unreachable;
                return result;
            },
            .ItemDefinition => return ControlFlowValidationError.ItemDefinitionInNonTopLevel,
            .IfStatement => |if_statement| {
                const condition_result = try self.validateTerminatesWithValue(if_statement.condition);
                if (condition_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                _ = try self.validateTerminatesWithValue(if_statement.then_branch);
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                return .FallsThroughWithoutValue;
            },
            .StructureConstruction => |structure_construction| {
                for (structure_construction.fields) |field| {
                    const result = try self.validateTerminatesWithValue(field.value);
                    if (result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .ExpressionStatement => |expression_statement| {
                const result = try self.validateTerminatesWithValue(expression_statement.expression);
                if (result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                } else {
                    self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                    return .FallsThroughWithoutValue;
                }
            },
            .Assignment => |assignment| {
                const target_result = try self.validateTerminatesWithValue(assignment.target);
                if (target_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }

                const result = try self.validateTerminatesWithValue(assignment.value);
                self.exit_behavior_by_node_id.put(assignment.value.id, result) catch unreachable;
                return result;
            },
            .Loop => |loop| {
                const result = try self.validateTerminatesWithValue(loop.body_block);
                self.exit_behavior_by_node_id.put(node.id, result) catch unreachable;
                return result;
            },
            .While => |while_statement| {
                const condition_result = try self.validateTerminatesWithValue(while_statement.condition);
                if (condition_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }

                if (while_statement.update) |update| {
                    const update_result = try self.validateTerminatesWithValue(update);
                    if (update_result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }

                _ = try self.validateTerminatesWithValue(while_statement.body_block);
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;

                return .FallsThroughWithoutValue;
            },
            .Leave => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                return .FallsThroughWithoutValue;
            },
            .Continue => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                return .FallsThroughWithoutValue;
            },
            .IfExpression => |if_expression| {
                const condition_result = try self.validateTerminatesWithValue(if_expression.condition);
                if (condition_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                const then_result = try self.validateTerminatesWithValue(if_expression.then_block);
                const else_result = try self.validateTerminatesWithValue(if_expression.else_block);
                if (then_result == .Terminates and else_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }

                if (then_result == .FallsThroughWithoutValue or else_result == .FallsThroughWithoutValue) {
                    self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                    return .FallsThroughWithoutValue;
                }

                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    const subject_result = try self.validateTerminatesWithValue(subject);
                    if (subject_result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }

                var saw_fallthrough_with_value = false;
                var saw_fallthrough_without_value = false;
                var any_arm_falls_through = false;

                for (match_expression.arms) |arm| {
                    const pattern_result = try self.validateTerminatesWithValue(arm.pattern_or_condition);
                    if (pattern_result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
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
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                if (saw_fallthrough_without_value) {
                    self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithoutValue) catch unreachable;
                    return .FallsThroughWithoutValue;
                }

                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .CallExpression => |call_expression| {
                const callee_result = try self.validateTerminatesWithValue(call_expression.callee);
                if (callee_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }

                for (call_expression.arguments) |*argument| {
                    const argument_result = try self.validateTerminatesWithValue(argument);
                    if (argument_result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }

                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;

                return .FallsThroughWithValue;
            },
            .BinaryExpression => |binary_expression| {
                const left_result = try self.validateTerminatesWithValue(binary_expression.left);
                if (left_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                const right_result = try self.validateTerminatesWithValue(binary_expression.right);
                if (right_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .UnaryExpression => |unary_expression| {
                const operand_result = try self.validateTerminatesWithValue(unary_expression.operand);
                if (operand_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .MemberAccess => |member_access| {
                const base_result = try self.validateTerminatesWithValue(member_access.base);
                if (base_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    const element_result = try self.validateTerminatesWithValue(element);
                    if (element_result == .Terminates) {
                        self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                        return .Terminates;
                    }
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .IndexAccess => |index_access| {
                const base_result = try self.validateTerminatesWithValue(index_access.base);
                if (base_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                const index_result = try self.validateTerminatesWithValue(index_access.index);
                if (index_result == .Terminates) {
                    self.exit_behavior_by_node_id.put(node.id, .Terminates) catch unreachable;
                    return .Terminates;
                }
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .Identifier => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .IntegerLiteral => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .BooleanLiteral => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
            .StringLiteral => {
                self.exit_behavior_by_node_id.put(node.id, .FallsThroughWithValue) catch unreachable;
                return .FallsThroughWithValue;
            },
        }
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
