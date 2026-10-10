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

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) !lowering_types.BinaryOperationDecisionByNodeId {
        var decision_by_node_id = lowering_types.BinaryOperationDecisionByNodeId.init(self.arena);

        for (analyzed_program.resolved_program.program.modules) |*module| {
            for (module.statements) |*statement| {
                try self.lowerNode(statement, analyzed_program, &decision_by_node_id);
            }
        }

        return decision_by_node_id;
    }

    fn lowerNode(
        self: *@This(),
        node: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.BinaryOperationDecisionByNodeId,
    ) !void {
        switch (node.kind) {
            .binding_declaration => |binding_declaration| try self.lowerNode(binding_declaration.value, analyzed_program, decision_by_node_id),
            .item_definition => |item_definition| switch (item_definition.definition) {
                .function => |function_definition| try self.lowerNode(function_definition.body_expression, analyzed_program, decision_by_node_id),
                inline .structure, .@"union" => |type_definition| {
                    for (type_definition.function_definitions) |*function_definition_node| {
                        try self.lowerNode(function_definition_node, analyzed_program, decision_by_node_id);
                    }
                },
            },
            .return_statement => |return_statement| {
                if (return_statement.value) |value| {
                    try self.lowerNode(value, analyzed_program, decision_by_node_id);
                }
            },
            .if_statement => |if_statement| {
                try self.lowerNode(if_statement.condition, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_statement.then_branch, analyzed_program, decision_by_node_id);
            },
            .expression_statement => |expression_statement| try self.lowerNode(expression_statement.expression, analyzed_program, decision_by_node_id),
            .assignment_statement => |assignment_statement| {
                try self.lowerNode(assignment_statement.target, analyzed_program, decision_by_node_id);
                try self.lowerNode(assignment_statement.value, analyzed_program, decision_by_node_id);
                switch (assignment_statement.operator) {
                    .assign => {},
                    .compound => |binary_operator| {
                        const target_type_id = analyzed_program.type_id_by_node_id.get(assignment_statement.target.id) orelse unreachable;
                        const decision = decisionFor(binary_operator, target_type_id, analyzed_program);
                        try decision_by_node_id.put(node.id, decision);
                    },
                }
            },
            .loop => |loop| try self.lowerNode(loop.body_block, analyzed_program, decision_by_node_id),
            .@"while" => |while_statement| {
                try self.lowerNode(while_statement.condition, analyzed_program, decision_by_node_id);
                if (while_statement.update) |update| {
                    try self.lowerNode(update, analyzed_program, decision_by_node_id);
                }
                try self.lowerNode(while_statement.body_block, analyzed_program, decision_by_node_id);
            },
            .for_in => |for_in| {
                try self.lowerNode(for_in.iterable, analyzed_program, decision_by_node_id);
                try self.lowerNode(for_in.body_block, analyzed_program, decision_by_node_id);
            },
            .if_expression => |if_expression| {
                try self.lowerNode(if_expression.condition, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_expression.then_block, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_expression.else_block, analyzed_program, decision_by_node_id);
            },
            .match_expression => |match_expression| {
                try self.lowerNode(match_expression.subject, analyzed_program, decision_by_node_id);
                const subject_type_id = analyzed_program.type_id_by_node_id.get(match_expression.subject.id) orelse unreachable;
                const subject_comparison_decision = decisionFor(.equal, subject_type_id, analyzed_program);
                try decision_by_node_id.put(node.id, subject_comparison_decision);
                for (match_expression.arms) |arm| {
                    try self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (match_expression.else_arm_expression) |else_arm_expression| {
                    try self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .subjectless_match_expression => |subjectless_match_expression| {
                for (subjectless_match_expression.arms) |arm| {
                    try self.lowerNode(arm.condition, analyzed_program, decision_by_node_id);
                    try self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (subjectless_match_expression.else_arm_expression) |else_arm_expression| {
                    try self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .call_expression => |call_expression| {
                try self.lowerNode(call_expression.callee, analyzed_program, decision_by_node_id);
                for (call_expression.arguments) |*argument| {
                    try self.lowerNode(argument, analyzed_program, decision_by_node_id);
                }
            },
            .member_expression => |member_expression| try self.lowerNode(member_expression.base, analyzed_program, decision_by_node_id),
            .binary_expression => |binary_expression| {
                try self.lowerNode(binary_expression.left, analyzed_program, decision_by_node_id);
                try self.lowerNode(binary_expression.right, analyzed_program, decision_by_node_id);
                try lowerBinaryExpression(node.id, &binary_expression, analyzed_program, decision_by_node_id);
            },
            .unary_expression => |unary_expression| try self.lowerNode(unary_expression.operand, analyzed_program, decision_by_node_id),
            .block => |block| {
                for (block.statements) |*statement| {
                    try self.lowerNode(statement, analyzed_program, decision_by_node_id);
                }
                if (block.result) |result| {
                    try self.lowerNode(result, analyzed_program, decision_by_node_id);
                }
            },
            .qualified_structure_literal => |qualified_structure_literal| {
                for (qualified_structure_literal.fields) |field| {
                    try self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .structure_literal => |structure_literal| {
                for (structure_literal.fields) |field| {
                    try self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .array_literal => |array_literal| {
                for (array_literal.elements) |*element| {
                    try self.lowerNode(element, analyzed_program, decision_by_node_id);
                }
            },
            .index_expression => |index_expression| {
                try self.lowerNode(index_expression.base, analyzed_program, decision_by_node_id);
                try self.lowerNode(index_expression.index, analyzed_program, decision_by_node_id);
            },
            .leave_statement,
            .continue_statement,
            .identifier,
            .integer_literal,
            .boolean_literal,
            .string_literal,
            .unit_literal,
            .implicit_member_expression,
            => {},
        }
    }

    fn lowerBinaryExpression(
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.BinaryOperationDecisionByNodeId,
    ) !void {
        const left_operand_type_id = analyzed_program.type_id_by_node_id.get(binary_expression.left.id) orelse unreachable;
        const decision = decisionFor(binary_expression.operator, left_operand_type_id, analyzed_program);
        try decision_by_node_id.put(node_id, decision);
    }

    fn decisionFor(
        binary_operator: ast.BinaryOperator,
        left_operand_type_id: typing.TypeId,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) lowering_types.BinaryOperationDecision {
        if (left_operand_type_id == analyzed_program.type_store.string_type_id) {
            return switch (binary_operator) {
                .add => .string_concatenate,
                .equal => .string_compare_equal,
                .not_equal => .string_compare_not_equal,
                else => unreachable,
            };
        }

        const left_operand_runtime_representation = analyzed_program
            .runtime_representation_result
            .runtime_representation_by_type_id
            .get(left_operand_type_id) orelse unreachable;
        if (!left_operand_runtime_representation.hasRuntimeRepresentation()) {
            return switch (binary_operator) {
                .equal => .zero_sized_compare_equal,
                .not_equal => .zero_sized_compare_not_equal,
                else => unreachable,
            };
        }

        switch (binary_operator) {
            .@"and" => return .short_circuit_and,
            .@"or" => return .short_circuit_or,
            .divide => return .checked_divide,
            else => {},
        }

        const left_operand_type = analyzed_program.type_store.getType(left_operand_type_id);
        if (left_operand_type == .@"union") {
            return switch (binary_operator) {
                .equal => .union_case_index_comparison,
                else => unreachable,
            };
        }

        return .{ .primitive_operation = switch (binary_operator) {
            .add => .add,
            .subtract => .subtract,
            .multiply => .multiply,
            .equal => .equal,
            .not_equal => .not_equal,
            .less_than => .less_than,
            .less_than_or_equal => .less_than_or_equal,
            .greater_than => .greater_than,
            .greater_than_or_equal => .greater_than_or_equal,
            .@"and",
            .@"or",
            .divide,
            => unreachable,
        } };
    }
};
