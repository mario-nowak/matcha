const std = @import("std");
const ast = @import("ast");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");

pub const BinaryOperationLowerer = struct {
    allocator: std.mem.Allocator,
    decision_by_node_id: lowering_types.BinaryOperationDecisionByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .decision_by_node_id = lowering_types.BinaryOperationDecisionByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.decision_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.BinaryOperationDecisionByNodeId {
        self.decision_by_node_id.clearRetainingCapacity();

        for (analyzed_program.resolved_program.program.statements) |*statement| {
            self.lowerNode(statement, analyzed_program);
        }

        return self.decision_by_node_id;
    }

    fn lowerNode(
        self: *@This(),
        node: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) void {
        switch (node.kind) {
            .Declaration => |declaration| self.lowerNode(declaration.value, analyzed_program),
            .ItemDefinition => |item_definition| switch (item_definition.item) {
                .Function => |function_definition| self.lowerNode(function_definition.body_expression, analyzed_program),
                .Structure => |structure_definition| {
                    for (structure_definition.function_definitions) |*function_definition_node| {
                        self.lowerNode(function_definition_node, analyzed_program);
                    }
                },
            },
            .Return => |return_statement| {
                if (return_statement.value) |value| {
                    self.lowerNode(value, analyzed_program);
                }
            },
            .IfStatement => |if_statement| {
                self.lowerNode(if_statement.condition, analyzed_program);
                self.lowerNode(if_statement.then_branch, analyzed_program);
            },
            .ExpressionStatement => |expression_statement| self.lowerNode(expression_statement.expression, analyzed_program),
            .Assignment => |assignment| {
                self.lowerNode(assignment.target, analyzed_program);
                self.lowerNode(assignment.value, analyzed_program);
            },
            .Loop => |loop| self.lowerNode(loop.body_block, analyzed_program),
            .Leave, .Continue, .Identifier, .IntegerLiteral, .BooleanLiteral, .StringLiteral, .UnitLiteral => {},
            .While => |while_statement| {
                self.lowerNode(while_statement.condition, analyzed_program);
                if (while_statement.update) |update| {
                    self.lowerNode(update, analyzed_program);
                }
                self.lowerNode(while_statement.body_block, analyzed_program);
            },
            .ForIn => |for_in| {
                self.lowerNode(for_in.iterable, analyzed_program);
                self.lowerNode(for_in.body_block, analyzed_program);
            },
            .IfExpression => |if_expression| {
                self.lowerNode(if_expression.condition, analyzed_program);
                self.lowerNode(if_expression.then_block, analyzed_program);
                self.lowerNode(if_expression.else_block, analyzed_program);
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    self.lowerNode(subject, analyzed_program);
                }
                for (match_expression.arms) |arm| {
                    self.lowerNode(arm.pattern_or_condition, analyzed_program);
                    self.lowerNode(arm.body, analyzed_program);
                }
                if (match_expression.else_arm) |else_arm| {
                    self.lowerNode(else_arm, analyzed_program);
                }
            },
            .CallExpression => |call_expression| {
                self.lowerNode(call_expression.callee, analyzed_program);
                for (call_expression.arguments) |*argument| {
                    self.lowerNode(argument, analyzed_program);
                }
            },
            .MemberAccess => |member_access| self.lowerNode(member_access.base, analyzed_program),
            .BinaryExpression => |binary_expression| {
                self.lowerNode(binary_expression.left, analyzed_program);
                self.lowerNode(binary_expression.right, analyzed_program);
                self.lowerBinaryExpression(node.id, &binary_expression, analyzed_program);
            },
            .UnaryExpression => |unary_expression| self.lowerNode(unary_expression.operand, analyzed_program),
            .Block => |block| {
                for (block.statements) |*statement| {
                    self.lowerNode(statement, analyzed_program);
                }
                if (block.result) |result| {
                    self.lowerNode(result, analyzed_program);
                }
            },
            .StructureConstruction => |structure_construction| {
                for (structure_construction.fields) |field| {
                    self.lowerNode(field.value, analyzed_program);
                }
            },
            .AnonymousStructureLiteral => |anonymous_structure_literal| {
                for (anonymous_structure_literal.fields) |field| {
                    self.lowerNode(field.value, analyzed_program);
                }
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    self.lowerNode(element, analyzed_program);
                }
            },
            .IndexAccess => |index_access| {
                self.lowerNode(index_access.base, analyzed_program);
                self.lowerNode(index_access.index, analyzed_program);
            },
        }
    }

    fn lowerBinaryExpression(
        self: *@This(),
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) void {
        const left_operand_type_id = analyzed_program.type_by_node_id.get(binary_expression.left.id) orelse unreachable;
        const decision = decisionFor(binary_expression.operator, left_operand_type_id, analyzed_program);
        self.decision_by_node_id.put(node_id, decision) catch unreachable;
    }

    pub fn decisionFor(
        binary_operator: ast.BinaryOperator,
        left_operand_type_id: typing.TypeId,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) lowering_types.BinaryOperationDecision {
        if (left_operand_type_id == analyzed_program.type_store.string_type_id) {
            return switch (binary_operator) {
                .Add => .StringConcatenate,
                .Equal => .StringCompareEqual,
                .NotEqual => .StringCompareNotEqual,
                else => unreachable,
            };
        }

        return .{ .PrimitiveOperation = switch (binary_operator) {
            .Add => .Add,
            .Subtract => .Subtract,
            .Multiply => .Multiply,
            .Divide => .Divide,
            .Equal => .Equal,
            .NotEqual => .NotEqual,
            .LessThan => .LessThan,
            .LessThanOrEqual => .LessThanOrEqual,
            .GreaterThan => .GreaterThan,
            .GreaterThanOrEqual => .GreaterThanOrEqual,
            .And => .And,
            .Or => .Or,
        } };
    }
};
