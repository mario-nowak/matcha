const std = @import("std");
const ast = @import("ast");

const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");

const lowering_types = @import("lowering_types.zig");

pub const CallLowerer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) !lowering_types.CallDispatchDecisionByNodeId {
        var decision_by_node_id = lowering_types.CallDispatchDecisionByNodeId.init(self.arena);

        for (analyzed_program.resolved_program.program.statements) |*statement| {
            try self.lowerNode(statement, analyzed_program, &decision_by_node_id);
        }

        return decision_by_node_id;
    }

    fn lowerNode(
        self: *@This(),
        node: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.CallDispatchDecisionByNodeId,
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
                try lowerCallExpression(node, &call_expression, analyzed_program, decision_by_node_id);
            },
            .member_expression => |member_expression| try self.lowerNode(member_expression.base, analyzed_program, decision_by_node_id),
            .binary_expression => |binary_expression| {
                try self.lowerNode(binary_expression.left, analyzed_program, decision_by_node_id);
                try self.lowerNode(binary_expression.right, analyzed_program, decision_by_node_id);
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

    fn lowerCallExpression(
        node: *const ast.Node,
        call_expression: *const ast.CallExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.CallDispatchDecisionByNodeId,
    ) !void {
        const callee_type_id = analyzed_program.type_id_by_node_id.get(call_expression.callee.id).?;
        const callee_type = analyzed_program.type_store.getType(callee_type_id);

        switch (callee_type) {
            .union_constructor => |union_constructor| {
                try decision_by_node_id.put(
                    node.id,
                    .{ .union_construction = .{
                        .union_type_id = union_constructor.union_type_id,
                        .case_index = union_constructor.case_index,
                    } },
                );
            },
            .function => {
                const decision: lowering_types.CallDispatchDecision = switch (call_expression.callee.kind) {
                    // An implicit member that is called names a type function of the expected union, so it has no receiver.
                    .implicit_member_expression => switch (analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable) {
                        .type_function_access => |type_function| .{
                            .user_function = .{
                                .function_symbol_id = type_function.function_symbol_id,
                            },
                        },
                        else => unreachable,
                    },
                    .member_expression => |callee_member_expression| switch (analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable) {
                        .instance_method_access => |instance_method| .{
                            .user_function = .{
                                .function_symbol_id = instance_method.function_symbol_id,
                                .receiver_node_id = callee_member_expression.base.id,
                            },
                        },
                        .type_function_access => |type_function| .{
                            .user_function = .{
                                .function_symbol_id = type_function.function_symbol_id,
                            },
                        },
                        .array_instance_method_access => |array_method| .{ .array_method = array_method },
                        .string_instance_method_access => |string_method| .{ .string_method = string_method },
                        .integer_instance_method_access => |integer_method| .{ .integer_method = integer_method },
                        else => unreachable,
                    },
                    else => lowerSymbolCall(call_expression.callee.id, analyzed_program),
                };

                try decision_by_node_id.put(node.id, decision);
            },
            else => unreachable,
        }
    }

    fn lowerSymbolCall(
        callee_node_id: ast.NodeId,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) lowering_types.CallDispatchDecision {
        const callee_symbol_id = analyzed_program.resolved_program.symbol_id_by_node_id.get(callee_node_id) orelse unreachable;
        const callee_symbol = analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
        const function_info = switch (callee_symbol.kind) {
            .function => |function| function,
            else => unreachable,
        };

        if (builtinCallKind(function_info.implementation_kind)) |builtin_call_kind| {
            return .{ .builtin = builtin_call_kind };
        }

        return .{ .user_function = .{ .function_symbol_id = callee_symbol_id } };
    }

    fn builtinCallKind(implementation_kind: symbols.FunctionImplementationKind) ?lowering_types.BuiltinCallKind {
        return switch (implementation_kind) {
            .builtin_print_int => .print_int,
            .builtin_print_string => .print_string,
            .builtin_read_file => .read_file,
            .builtin_read_line => .read_line,
            .builtin_get_arguments => .get_arguments,
            .user_defined => null,
        };
    }
};
