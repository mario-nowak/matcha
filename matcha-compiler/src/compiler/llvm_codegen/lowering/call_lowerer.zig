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
            .BindingDeclaration => |binding_declaration| try self.lowerNode(binding_declaration.value, analyzed_program, decision_by_node_id),
            .ItemDefinition => |item_definition| switch (item_definition.definition) {
                .Function => |function_definition| try self.lowerNode(function_definition.body_expression, analyzed_program, decision_by_node_id),
                inline .Structure, .Union => |type_definition| {
                    for (type_definition.function_definitions) |*function_definition_node| {
                        try self.lowerNode(function_definition_node, analyzed_program, decision_by_node_id);
                    }
                },
            },
            .ReturnStatement => |return_statement| {
                if (return_statement.value) |value| {
                    try self.lowerNode(value, analyzed_program, decision_by_node_id);
                }
            },
            .IfStatement => |if_statement| {
                try self.lowerNode(if_statement.condition, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_statement.then_branch, analyzed_program, decision_by_node_id);
            },
            .ExpressionStatement => |expression_statement| try self.lowerNode(expression_statement.expression, analyzed_program, decision_by_node_id),
            .AssignmentStatement => |assignment_statement| {
                try self.lowerNode(assignment_statement.target, analyzed_program, decision_by_node_id);
                try self.lowerNode(assignment_statement.value, analyzed_program, decision_by_node_id);
            },
            .Loop => |loop| try self.lowerNode(loop.body_block, analyzed_program, decision_by_node_id),
            .While => |while_statement| {
                try self.lowerNode(while_statement.condition, analyzed_program, decision_by_node_id);
                if (while_statement.update) |update| {
                    try self.lowerNode(update, analyzed_program, decision_by_node_id);
                }
                try self.lowerNode(while_statement.body_block, analyzed_program, decision_by_node_id);
            },
            .ForIn => |for_in| {
                try self.lowerNode(for_in.iterable, analyzed_program, decision_by_node_id);
                try self.lowerNode(for_in.body_block, analyzed_program, decision_by_node_id);
            },
            .IfExpression => |if_expression| {
                try self.lowerNode(if_expression.condition, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_expression.then_block, analyzed_program, decision_by_node_id);
                try self.lowerNode(if_expression.else_block, analyzed_program, decision_by_node_id);
            },
            .MatchExpression => |match_expression| {
                try self.lowerNode(match_expression.subject, analyzed_program, decision_by_node_id);
                for (match_expression.arms) |arm| {
                    try self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (match_expression.else_arm_expression) |else_arm_expression| {
                    try self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .SubjectlessMatchExpression => |subjectless_match_expression| {
                for (subjectless_match_expression.arms) |arm| {
                    try self.lowerNode(arm.condition, analyzed_program, decision_by_node_id);
                    try self.lowerNode(arm.body_expression, analyzed_program, decision_by_node_id);
                }
                if (subjectless_match_expression.else_arm_expression) |else_arm_expression| {
                    try self.lowerNode(else_arm_expression, analyzed_program, decision_by_node_id);
                }
            },
            .CallExpression => |call_expression| {
                try self.lowerNode(call_expression.callee, analyzed_program, decision_by_node_id);
                for (call_expression.arguments) |*argument| {
                    try self.lowerNode(argument, analyzed_program, decision_by_node_id);
                }
                try lowerCallExpression(node, &call_expression, analyzed_program, decision_by_node_id);
            },
            .MemberExpression => |member_expression| try self.lowerNode(member_expression.base, analyzed_program, decision_by_node_id),
            .BinaryExpression => |binary_expression| {
                try self.lowerNode(binary_expression.left, analyzed_program, decision_by_node_id);
                try self.lowerNode(binary_expression.right, analyzed_program, decision_by_node_id);
            },
            .UnaryExpression => |unary_expression| try self.lowerNode(unary_expression.operand, analyzed_program, decision_by_node_id),
            .Block => |block| {
                for (block.statements) |*statement| {
                    try self.lowerNode(statement, analyzed_program, decision_by_node_id);
                }
                if (block.result) |result| {
                    try self.lowerNode(result, analyzed_program, decision_by_node_id);
                }
            },
            .QualifiedStructureLiteral => |qualified_structure_literal| {
                for (qualified_structure_literal.fields) |field| {
                    try self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .StructureLiteral => |structure_literal| {
                for (structure_literal.fields) |field| {
                    try self.lowerNode(field.value, analyzed_program, decision_by_node_id);
                }
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    try self.lowerNode(element, analyzed_program, decision_by_node_id);
                }
            },
            .IndexExpression => |index_expression| {
                try self.lowerNode(index_expression.base, analyzed_program, decision_by_node_id);
                try self.lowerNode(index_expression.index, analyzed_program, decision_by_node_id);
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

    fn lowerCallExpression(
        node: *const ast.Node,
        call_expression: *const ast.CallExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.CallDispatchDecisionByNodeId,
    ) !void {
        const callee_type_id = analyzed_program.type_id_by_node_id.get(call_expression.callee.id).?;
        const callee_type = analyzed_program.type_store.getType(callee_type_id);

        switch (callee_type) {
            .UnionConstructor => |union_constructor| {
                try decision_by_node_id.put(
                    node.id,
                    .{ .UnionConstruction = .{
                        .union_type_id = union_constructor.union_type_id,
                        .case_index = union_constructor.case_index,
                    } },
                );
            },
            .Function => {
                const decision: lowering_types.CallDispatchDecision = switch (call_expression.callee.kind) {
                    // An implicit member that is called names a type function of the expected union, so it has no receiver.
                    .ImplicitMemberExpression => switch (analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable) {
                        .TypeFunctionAccess => |type_function| .{
                            .UserFunction = .{
                                .function_symbol_id = type_function.function_symbol_id,
                            },
                        },
                        else => unreachable,
                    },
                    .MemberExpression => |callee_member_expression| switch (analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable) {
                        .InstanceMethodAccess => |instance_method| .{
                            .UserFunction = .{
                                .function_symbol_id = instance_method.function_symbol_id,
                                .receiver_node_id = callee_member_expression.base.id,
                            },
                        },
                        .TypeFunctionAccess => |type_function| .{
                            .UserFunction = .{
                                .function_symbol_id = type_function.function_symbol_id,
                            },
                        },
                        .ArrayInstanceMethodAccess => |array_method| .{ .ArrayMethod = array_method },
                        .StringInstanceMethodAccess => |string_method| .{ .StringMethod = string_method },
                        .IntegerInstanceMethodAccess => |integer_method| .{ .IntegerMethod = integer_method },
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
            .Function => |function| function,
            else => unreachable,
        };

        if (builtinCallKind(function_info.implementation_kind)) |builtin_call_kind| {
            return .{ .Builtin = builtin_call_kind };
        }

        return .{ .UserFunction = .{ .function_symbol_id = callee_symbol_id } };
    }

    fn builtinCallKind(implementation_kind: symbols.FunctionImplementationKind) ?lowering_types.BuiltinCallKind {
        return switch (implementation_kind) {
            .BuiltinPrintInt => .PrintInt,
            .BuiltinPrintString => .PrintString,
            .BuiltinReadFile => .ReadFile,
            .BuiltinReadLine => .ReadLine,
            .BuiltinGetArguments => .GetArguments,
            .UserDefined => null,
        };
    }
};
