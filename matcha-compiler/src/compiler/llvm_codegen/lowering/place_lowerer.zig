const std = @import("std");
const ast = @import("ast");
const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const PlaceLowerer = struct {
    allocator: std.mem.Allocator,
    decision_by_node_id: lowering_types.PlaceDecisionByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .decision_by_node_id = lowering_types.PlaceDecisionByNodeId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.decision_by_node_id.deinit();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.PlaceDecisionByNodeId {
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
                self.lowerPlace(assignment.target, analyzed_program);
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

    fn lowerPlace(
        self: *@This(),
        target: *const ast.Node,
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) void {
        const decision: lowering_types.PlaceDecision = switch (target.kind) {
            .Identifier => .{ .IdentifierBinding = .{
                .symbol_id = analyzed_program.resolved_program.symbol_id_by_node_id.get(target.id) orelse unreachable,
            } },
            .MemberAccess => .{ .StructureField = .{
                .field_index = switch (analyzed_program.member_access_by_node_id.get(target.id) orelse unreachable) {
                    .StructureInstanceFieldAccess => |structure_field| structure_field.field_index,
                    else => unreachable,
                },
            } },
            .IndexAccess => .ArrayElement,
            else => unreachable,
        };

        self.decision_by_node_id.put(target.id, decision) catch unreachable;
    }
};
