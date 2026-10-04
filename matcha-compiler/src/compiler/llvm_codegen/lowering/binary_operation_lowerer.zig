const std = @import("std");
const ast = @import("ast");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");

pub const BinaryOperationLowerer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.BinaryOperationDecisionByNodeId {
        var decision_by_node_id = lowering_types.BinaryOperationDecisionByNodeId.init(self.arena);

        for (analyzed_program.resolved_program.program.statements) |*statement| {
            self.lowerNode(statement, analyzed_program, &decision_by_node_id);
        }

        return decision_by_node_id;
    }

    fn lowerNode(
        self: *@This(),
        node: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.BinaryOperationDecisionByNodeId,
    ) void {
        switch (node.kind) {
            .BindingDeclaration => |binding_declaration| self.lowerNode(binding_declaration.value, analyzed_program, decision_by_node_id),
            .ItemDefinition => |item_definition| switch (item_definition.definition) {
                .Function => |function_definition| self.lowerNode(function_definition.body_expression, analyzed_program, decision_by_node_id),
                inline .Structure, .Union => |type_definition| {
                    for (type_definition.function_definitions) |*function_definition_node| {
                        self.lowerNode(function_definition_node, analyzed_program, decision_by_node_id);
                    }
                },
            },
            .ReturnStatement => |return_statement| {
                if (return_statement.value) |value| {
                    self.lowerNode(value, analyzed_program, decision_by_node_id);
                }
            },
            .IfStatement => |if_statement| {
                self.lowerNode(if_statement.condition, analyzed_program, decision_by_node_id);
                self.lowerNode(if_statement.then_branch, analyzed_program, decision_by_node_id);
            },
            .ExpressionStatement => |expression_statement| self.lowerNode(expression_statement.expression, analyzed_program, decision_by_node_id),
            .AssignmentStatement => |assignment_statement| {
                self.lowerNode(assignment_statement.target, analyzed_program, decision_by_node_id);
                self.lowerNode(assignment_statement.value, analyzed_program, decision_by_node_id);
                switch (assignment_statement.operator) {
                    .Assign => {},
                    .Compound => |binary_operator| {
                        const target_type_id = analyzed_program.type_id_by_node_id.get(assignment_statement.target.id) orelse unreachable;
                        const decision = decisionFor(binary_operator, target_type_id, analyzed_program);
                        decision_by_node_id.put(node.id, decision) catch unreachable;
                    },
                }
            },
            .Loop => |loop| self.lowerNode(loop.body_block, analyzed_program, decision_by_node_id),
            .While => |while_statement| {
                self.lowerNode(while_statement.condition, analyzed_program, decision_by_node_id);
                if (while_statement.update) |update| {
                    self.lowerNode(update, analyzed_program, decision_by_node_id);
                }
                self.lowerNode(while_statement.body_block, analyzed_program, decision_by_node_id);
            },
            .ForIn => |for_in| {
                self.lowerNode(for_in.iterable, analyzed_program, decision_by_node_id);
                self.lowerNode(for_in.body_block, analyzed_program, decision_by_node_id);
            },
            .IfExpression => |if_expression| {
                self.lowerNode(if_expression.condition, analyzed_program, decision_by_node_id);
                self.lowerNode(if_expression.then_block, analyzed_program, decision_by_node_id);
                self.lowerNode(if_expression.else_block, analyzed_program, decision_by_node_id);
            },
            .MatchExpression => |match_expression| {
                self.lowerNode(match_expression.subject, analyzed_program, decision_by_node_id);
                const subject_type_id = analyzed_program.type_id_by_node_id.get(match_expression.subject.id) orelse unreachable;
                const subject_comparison_decision = decisionFor(.Equal, subject_type_id, analyzed_program);
                decision_by_node_id.put(node.id, subject_comparison_decision) catch unreachable;
                for (match_expression.arms) |arm| {
                    self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (match_expression.else_arm_expression) |else_arm_expression| {
                    self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .SubjectlessMatchExpression => |subjectless_match_expression| {
                for (subjectless_match_expression.arms) |arm| {
                    self.lowerNode(arm.condition, analyzed_program, decision_by_node_id);
                    self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (subjectless_match_expression.else_arm_expression) |else_arm_expression| {
                    self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .CallExpression => |call_expression| {
                self.lowerNode(call_expression.callee, analyzed_program, decision_by_node_id);
                for (call_expression.arguments) |*argument| {
                    self.lowerNode(argument, analyzed_program, decision_by_node_id);
                }
            },
            .MemberExpression => |member_expression| self.lowerNode(member_expression.base, analyzed_program, decision_by_node_id),
            .BinaryExpression => |binary_expression| {
                self.lowerNode(binary_expression.left, analyzed_program, decision_by_node_id);
                self.lowerNode(binary_expression.right, analyzed_program, decision_by_node_id);
                lowerBinaryExpression(node.id, &binary_expression, analyzed_program, decision_by_node_id);
            },
            .UnaryExpression => |unary_expression| self.lowerNode(unary_expression.operand, analyzed_program, decision_by_node_id),
            .Block => |block| {
                for (block.statements) |*statement| {
                    self.lowerNode(statement, analyzed_program, decision_by_node_id);
                }
                if (block.result) |result| {
                    self.lowerNode(result, analyzed_program, decision_by_node_id);
                }
            },
            .QualifiedStructureLiteral => |qualified_structure_literal| {
                for (qualified_structure_literal.fields) |field| {
                    self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .StructureLiteral => |structure_literal| {
                for (structure_literal.fields) |field| {
                    self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    self.lowerNode(element, analyzed_program, decision_by_node_id);
                }
            },
            .IndexExpression => |index_expression| {
                self.lowerNode(index_expression.base, analyzed_program, decision_by_node_id);
                self.lowerNode(index_expression.index, analyzed_program, decision_by_node_id);
            },
            .LeaveStatement,
            .ContinueStatement,
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .UnitLiteral,
            .ImplicitMemberExpression,
            => {},
        }
    }

    fn lowerBinaryExpression(
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.BinaryOperationDecisionByNodeId,
    ) void {
        const left_operand_type_id = analyzed_program.type_id_by_node_id.get(binary_expression.left.id) orelse unreachable;
        const decision = decisionFor(binary_expression.operator, left_operand_type_id, analyzed_program);
        decision_by_node_id.put(node_id, decision) catch unreachable;
    }

    fn decisionFor(
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

        const left_operand_runtime_representation = analyzed_program
            .runtime_representation_result
            .runtime_representation_by_type_id
            .get(left_operand_type_id) orelse unreachable;
        if (!left_operand_runtime_representation.hasRuntimeRepresentation()) {
            return switch (binary_operator) {
                .Equal => .ZeroSizedCompareEqual,
                .NotEqual => .ZeroSizedCompareNotEqual,
                else => unreachable,
            };
        }

        switch (binary_operator) {
            .And => return .ShortCircuitAnd,
            .Or => return .ShortCircuitOr,
            .Divide => return .CheckedDivide,
            else => {},
        }

        const left_operand_type = analyzed_program.type_store.getType(left_operand_type_id);
        if (left_operand_type == .Union) {
            return switch (binary_operator) {
                .Equal => .UnionCaseIndexComparison,
                else => unreachable,
            };
        }

        return .{ .PrimitiveOperation = switch (binary_operator) {
            .Add => .Add,
            .Subtract => .Subtract,
            .Multiply => .Multiply,
            .Equal => .Equal,
            .NotEqual => .NotEqual,
            .LessThan => .LessThan,
            .LessThanOrEqual => .LessThanOrEqual,
            .GreaterThan => .GreaterThan,
            .GreaterThanOrEqual => .GreaterThanOrEqual,
            .And,
            .Or,
            .Divide,
            => unreachable,
        } };
    }
};
