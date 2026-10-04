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

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.CallDispatchDecisionByNodeId {
        var decision_by_node_id = lowering_types.CallDispatchDecisionByNodeId.init(self.arena);

        for (analyzed_program.resolved_program.program.statements) |*statement| {
            self.lowerNode(statement, analyzed_program, &decision_by_node_id);
        }

        return decision_by_node_id;
    }

    fn lowerNode(
        self: *@This(),
        node: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.CallDispatchDecisionByNodeId,
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
                lowerCallExpression(node, &call_expression, analyzed_program, decision_by_node_id);
            },
            .MemberExpression => |member_expression| self.lowerNode(member_expression.base, analyzed_program, decision_by_node_id),
            .BinaryExpression => |binary_expression| {
                self.lowerNode(binary_expression.left, analyzed_program, decision_by_node_id);
                self.lowerNode(binary_expression.right, analyzed_program, decision_by_node_id);
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

    fn lowerCallExpression(
        node: *const ast.Node,
        call_expression: *const ast.CallExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        decision_by_node_id: *lowering_types.CallDispatchDecisionByNodeId,
    ) void {
        const callee_type_id = analyzed_program.type_id_by_node_id.get(call_expression.callee.id).?;
        const callee_type = analyzed_program.type_store.getType(callee_type_id);

        switch (callee_type) {
            .UnionConstructor => |union_constructor| {
                decision_by_node_id.put(
                    node.id,
                    .{ .UnionConstruction = .{
                        .union_type_id = union_constructor.union_type_id,
                        .case_index = union_constructor.case_index,
                    } },
                ) catch unreachable;
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

                decision_by_node_id.put(node.id, decision) catch unreachable;
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
