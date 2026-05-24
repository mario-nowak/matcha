const std = @import("std");
const ast = @import("ast");
const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const lowering_types = @import("lowering_types.zig");

pub const CallLowerer = struct {
    allocator: std.mem.Allocator,
    decision_by_node_id: lowering_types.CallDispatchDecisionByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .decision_by_node_id = lowering_types.CallDispatchDecisionByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.decision_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.CallDispatchDecisionByNodeId {
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
                self.lowerCallExpression(node, &call_expression, analyzed_program);
            },
            .MemberAccess => |member_access| self.lowerNode(member_access.base, analyzed_program),
            .BinaryExpression => |binary_expression| {
                self.lowerNode(binary_expression.left, analyzed_program);
                self.lowerNode(binary_expression.right, analyzed_program);
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

    fn lowerCallExpression(
        self: *@This(),
        node: *const ast.Node,
        call_expression: *const ast.CallExpression,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) void {
        const decision: lowering_types.CallDispatchDecision = switch (call_expression.callee.kind) {
            .MemberAccess => |callee_member_access| switch (analyzed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable) {
                .StructureInstanceMethodAccess => |structure_method| .{
                    .UserFunction = .{
                        .function_symbol_id = structure_method.function_symbol_id,
                        .owning_structure_symbol_id = structure_method.structure_symbol_id,
                        .receiver_node_id = callee_member_access.base.id,
                    },
                },
                .StructureTypeFunctionAccess => |structure_function| .{
                    .UserFunction = .{
                        .function_symbol_id = structure_function.function_symbol_id,
                        .owning_structure_symbol_id = structure_function.structure_symbol_id,
                    },
                },
                .ArrayInstanceMethodAccess => |array_method| .{ .ArrayMethod = array_method },
                .StringInstanceMethodAccess => |string_method| .{ .StringMethod = string_method },
                .IntegerInstanceMethodAccess => |integer_method| .{ .IntegerMethod = integer_method },
                else => unreachable,
            },
            else => self.lowerSymbolCall(call_expression.callee.id, analyzed_program),
        };

        self.decision_by_node_id.put(node.id, decision) catch unreachable;
    }

    fn lowerSymbolCall(
        self: *const @This(),
        callee_node_id: ast.NodeId,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) lowering_types.CallDispatchDecision {
        _ = self;

        const callee_symbol_id = analyzed_program.resolved_program.symbol_id_by_node_id.get(callee_node_id) orelse unreachable;
        const callee_symbol = analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
        const function_info = switch (callee_symbol.kind) {
            .Function => |function| function,
            else => unreachable,
        };

        if (builtinCallKind(function_info.implementation)) |builtin_call_kind| {
            return .{ .Builtin = builtin_call_kind };
        }

        return .{ .UserFunction = .{ .function_symbol_id = callee_symbol_id } };
    }

    fn builtinCallKind(implementation: symbols.Implementation) ?lowering_types.BuiltinCallKind {
        return switch (implementation) {
            .BuiltinPrintInt => .PrintInt,
            .BuiltinPrintString => .PrintString,
            .BuiltinReadFile => .ReadFile,
            .BuiltinReadLine => .ReadLine,
            .BuiltinGetArguments => .GetArguments,
            .UserDefined => null,
        };
    }
};
