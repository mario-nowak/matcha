const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");

const ValidationContext = enum {
    Statement,
    Expression,
    FunctionBody,
};

const ExhaustivenessClass = enum {
    Boolean,
    IntegerOpen,
    Subjectless,
};

const TypeError = error{
    BlockMustProduceValue,
    BlockCannotProduceValue,
    TypeMismatch,
    NonExhaustiveMatch,
    DuplicateMatchArm,
};

pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    type_store: typing.TypeStore,
    type_by_symbol_id: typing.TypeBySymbolId,
    type_by_node_id: typing.TypeByNodeId,
    structure_construction_layout_by_node_id: typing.StructureConstructionLayoutByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .type_store = typing.TypeStore.init(allocator),
            .type_by_symbol_id = typing.TypeBySymbolId.init(allocator),
            .type_by_node_id = typing.TypeByNodeId.init(allocator),
            .structure_construction_layout_by_node_id = typing.StructureConstructionLayoutByNodeId.init(allocator),
        };
    }

    pub fn checkProgram(
        self: *@This(),
        resolved_program: symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypedProgram {
        self.type_store = typing.TypeStore.init(self.allocator);
        self.type_by_symbol_id = typing.TypeBySymbolId.init(self.allocator);
        self.type_by_node_id = typing.TypeByNodeId.init(self.allocator);
        self.structure_construction_layout_by_node_id = typing.StructureConstructionLayoutByNodeId.init(self.allocator);
        const context: ValidationContext = .Statement;

        try self.seedModuleLevelItemTypes(&resolved_program);

        for (resolved_program.program.statements) |*statement| {
            _ = try self.checkNode(
                statement,
                &resolved_program,
                exit_behavior_by_node_id,
                context,
            );
        }

        return .{
            .resolved_program = resolved_program,
            .type_store = self.type_store,
            .type_by_symbol_id = self.type_by_symbol_id,
            .type_by_node_id = self.type_by_node_id,
            .structure_construction_layout_by_node_id = self.structure_construction_layout_by_node_id,
        };
    }

    fn seedModuleLevelItemTypes(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        var resolved_items_iterator = resolved_program.resolved_item_by_symbol_id.valueIterator();
        while (resolved_items_iterator.next()) |item| {
            switch (item.*) {
                .Function => {},
                .Structure => |structure| {
                    const structure_type_id: typing.StructureTypeId = @intCast(self.type_store.structure_types.items.len);
                    self.type_store.structure_types.append(self.allocator, .{
                        .name = structure.name,
                        .fields = &.{},
                        .field_index_by_name = std.StringHashMap(u32).init(self.allocator),
                    }) catch unreachable;
                    const type_id = self.type_store.addType(.{ .Structure = structure_type_id });
                    self.type_by_symbol_id.put(structure.symbol_id, type_id) catch unreachable;
                },
            }
        }

        resolved_items_iterator = resolved_program.resolved_item_by_symbol_id.valueIterator();
        while (resolved_items_iterator.next()) |item| {
            switch (item.*) {
                .Function => |function| {
                    const function_return_type = self.resolveTypeReference(function.return_type_reference);
                    self.type_by_symbol_id.put(function.symbol_id, function_return_type) catch unreachable;
                    for (function.parameters) |parameter| {
                        const parameter_type = self.resolveTypeReference(parameter.type_reference);
                        self.type_by_symbol_id.put(parameter.symbol_id, parameter_type) catch unreachable;
                    }
                },
                .Structure => |structure| {
                    const type_id = self.type_by_symbol_id.get(structure.symbol_id).?;
                    const structure_type_id = switch (self.type_store.getType(type_id)) {
                        .Structure => |id| id,
                        else => unreachable,
                    };

                    var fields = std.ArrayList(typing.Field){};
                    var field_index_by_name = std.StringHashMap(u32).init(self.allocator);
                    for (structure.fields, 0..) |field, index| {
                        fields.append(self.allocator, .{
                            .name = field.name,
                            .type_id = self.resolveTypeReference(field.type_reference),
                        }) catch unreachable;
                        field_index_by_name.put(field.name, @intCast(index)) catch unreachable;
                    }

                    self.type_store.structure_types.items[structure_type_id] = .{
                        .name = structure.name,
                        .fields = fields.toOwnedSlice(self.allocator) catch unreachable,
                        .field_index_by_name = field_index_by_name,
                    };
                },
            }
        }
    }

    fn checkNode(
        self: *@This(),
        node: *const ast.Node,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.TypeId {
        switch (node.kind) {
            .Declaration => |declaration| return self.checkDeclarationNode(node.id, &declaration, resolved_program, exit_behavior_by_node_id),
            .ItemDefinition => |item_definition| return self.checkItemDefinitionNode(node.id, &item_definition, resolved_program, exit_behavior_by_node_id),
            .Return => |return_statement| return self.checkReturnNode(node.id, &return_statement, resolved_program, exit_behavior_by_node_id),
            .Assignment => |assignment| return self.checkAssignmentNode(node.id, &assignment, resolved_program, exit_behavior_by_node_id),
            .Loop => |loop| return self.checkLoopNode(node.id, &loop, resolved_program, exit_behavior_by_node_id),
            .While => |while_statement| return self.checkWhileNode(node.id, &while_statement, resolved_program, exit_behavior_by_node_id),
            .Leave => return self.checkLeaveNode(node.id),
            .Continue => return self.checkContinueNode(node.id),
            .CallExpression => |call_expression| return self.checkCallExpressionNode(node.id, &call_expression, resolved_program, exit_behavior_by_node_id),
            .FieldAccess => |field_access| return self.checkFieldAccessNode(node.id, &field_access, resolved_program, exit_behavior_by_node_id),
            .BinaryExpression => |binary_expression| return self.checkBinaryExpressionNode(node.id, &binary_expression, resolved_program, exit_behavior_by_node_id),
            .UnaryExpression => |unary_expression| return self.checkUnaryExpressionNode(node.id, &unary_expression, resolved_program, exit_behavior_by_node_id),
            .StructureConstruction => |structure_construction| return self.checkStructureConstructionNode(node.id, &structure_construction, resolved_program, exit_behavior_by_node_id),
            .Block => |block| return self.checkBlockNode(node.id, &block, resolved_program, exit_behavior_by_node_id, context),
            .IntegerLiteral => return self.checkIntegerLiteralNode(node.id),
            .BooleanLiteral => return self.checkBooleanLiteralNode(node.id),
            .StringLiteral => return self.checkStringLiteralNode(node.id),
            .Identifier => return self.checkIdentifierNode(node.id, resolved_program),
            .IfStatement => |if_statement| return self.checkIfStatementNode(node.id, &if_statement, resolved_program, exit_behavior_by_node_id),
            .IfExpression => |if_expression| return self.checkIfExpressionNode(node.id, &if_expression, resolved_program, exit_behavior_by_node_id, context),
            .MatchExpression => |match_expression| return self.checkMatchExpressionNode(node.id, &match_expression, resolved_program, exit_behavior_by_node_id, context),
            .ExpressionStatement => |expression_statement| return self.checkExpressionStatementNode(node.id, &expression_statement, resolved_program, exit_behavior_by_node_id),
        }
    }

    fn checkItemDefinitionNode(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: *const ast.ItemDefinition,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        switch (item_definition.item) {
            .Function => |function_definition| try self.checkFunctionDefinition(
                node_id,
                &function_definition,
                resolved_program,
                exit_behavior_by_node_id,
            ),
            .Structure => {},
        }
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkStructureConstructionNode(
        self: *@This(),
        node_id: ast.NodeId,
        structure_construction: *const ast.StructureConstruction,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const structure_symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        const type_id = self.type_by_symbol_id.get(structure_symbol_id).?;
        const structure_construction_type = self.type_store.getType(type_id);
        const structure_type_id = switch (structure_construction_type) {
            .Structure => |structure_type_id| structure_type_id,
            else => {
                std.debug.print(
                    "Type Error: Expected structure type for structure construction, got {any}\n",
                    .{self.getType(type_id)},
                );
                return TypeError.TypeMismatch;
            },
        };
        const structure_type = self.type_store.structure_types.items[structure_type_id];

        var unique_field_names = std.StringHashMap(bool).init(self.allocator);
        defer unique_field_names.deinit();
        var field_indices = std.ArrayList(u32){};
        defer field_indices.deinit(self.allocator);

        for (structure_construction.fields) |field| {
            const field_name = field.name.kind.Identifier;
            const existing_field_name = unique_field_names.get(field_name);
            if (existing_field_name) |_| {
                std.debug.print(
                    "Type Error: Duplicate field name in structure construction: {s}\n",
                    .{field_name},
                );
                return TypeError.TypeMismatch;
            }
            unique_field_names.put(field_name, true) catch unreachable;

            const field_index = structure_type.field_index_by_name.get(field_name) orelse {
                std.debug.print(
                    "Type Error: No field named {s} exists on structure type {s}\n",
                    .{ field_name, structure_type.name },
                );
                return TypeError.TypeMismatch;
            };
            const structure_type_field = structure_type.fields[@intCast(field_index)];
            const field_value_type_id = try self.checkNode(
                field.value,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );

            if (structure_type_field.type_id != field_value_type_id) {
                std.debug.print(
                    "Type Error: Field {s} of structure type {s} expected type {any}, got {any}\n",
                    .{ field_name, structure_type.name, self.getType(structure_type_field.type_id), self.getType(field_value_type_id) },
                );
                return TypeError.TypeMismatch;
            }

            field_indices.append(self.allocator, field_index) catch unreachable;
        }

        for (structure_type.fields) |field| {
            const field_exists_in_construction = unique_field_names.get(field.name);
            if (field_exists_in_construction == null) {
                std.debug.print(
                    "Type Error: Field {s} of structure type {s} is missing in structure construction\n",
                    .{ field.name, structure_type.name },
                );
                return TypeError.TypeMismatch;
            }
        }

        self.structure_construction_layout_by_node_id.put(node_id, .{
            .field_indices = field_indices.toOwnedSlice(self.allocator) catch unreachable,
        }) catch unreachable;

        return self.recordNodeType(node_id, type_id);
    }

    fn checkDeclarationNode(
        self: *@This(),
        node_id: ast.NodeId,
        declaration: *const ast.Declaration,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const value_type = try self.checkNode(
            declaration.value,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const annotated_type = if (declaration.type_annotation) |type_annotation|
            self.resolveTypeAnnotation(type_annotation, resolved_program)
        else
            null;
        if (annotated_type) |annotated| {
            if (annotated != value_type) {
                std.debug.print(
                    "Type Error: Value declaration annotation does not match initializer type, expected {any}, got {any}\n",
                    .{ self.getType(annotated), self.getType(value_type) },
                );
                return TypeError.TypeMismatch;
            }
        }

        const symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        self.type_by_symbol_id.put(symbol_id, value_type) catch unreachable;
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkReturnNode(
        self: *@This(),
        node_id: ast.NodeId,
        return_statement: *const ast.Return,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        if (return_statement.value) |return_value| {
            _ = try self.checkNode(
                return_value,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkAssignmentNode(
        self: *@This(),
        node_id: ast.NodeId,
        assignment: *const ast.Assignment,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const target_type = try self.checkNode(
            assignment.target,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const value_type = try self.checkNode(
            assignment.value,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (target_type != value_type) {
            std.debug.print(
                "Type Error: Cannot assign value of type {any} to target of type {any}\n",
                .{ self.getType(value_type), self.getType(target_type) },
            );
            return TypeError.TypeMismatch;
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkLoopNode(
        self: *@This(),
        node_id: ast.NodeId,
        loop: *const ast.Loop,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        _ = try self.checkNode(
            loop.body_block,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkWhileNode(
        self: *@This(),
        node_id: ast.NodeId,
        while_statement: *const ast.While,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const while_condition_type = try self.checkNode(
            while_statement.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (while_condition_type != self.type_store.boolean_type_id) {
            std.debug.print(
                "Type Error: While condition must be of type boolean, got {any}\n",
                .{self.getType(while_condition_type)},
            );
            return TypeError.TypeMismatch;
        }

        if (while_statement.update) |update| {
            _ = try self.checkNode(
                update,
                resolved_program,
                exit_behavior_by_node_id,
                .Statement,
            );
        }

        _ = try self.checkNode(
            while_statement.body_block,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkLeaveNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkContinueNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkCallExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        call_expression: *const ast.CallExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        switch (call_expression.callee.kind) {
            .Identifier => {
                const callee_symbol_id = resolved_program.symbol_id_by_node_id.get(
                    call_expression.callee.id,
                ) orelse unreachable;
                const resolved_function = self.getResolvedFunction(callee_symbol_id, resolved_program);
                if (call_expression.arguments.len != resolved_function.parameters.len) {
                    std.debug.print(
                        "Type Error: Function expected {any} arguments, got {any}\n",
                        .{ resolved_function.parameters.len, call_expression.arguments.len },
                    );
                    return TypeError.TypeMismatch;
                }

                for (call_expression.arguments, resolved_function.parameters) |*argument, parameter| {
                    const argument_type = try self.checkNode(
                        argument,
                        resolved_program,
                        exit_behavior_by_node_id,
                        .Expression,
                    );
                    const parameter_type = self.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
                    if (argument_type != parameter_type) {
                        std.debug.print(
                            "Type Error: Function parameter expected type {any}, got {any}\n",
                            .{ self.getType(parameter_type), self.getType(argument_type) },
                        );
                        return TypeError.TypeMismatch;
                    }
                }

                const function_return_type = self.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                return self.recordNodeType(node_id, function_return_type);
            },
            else => return TypeError.TypeMismatch,
        }
    }

    fn checkFieldAccessNode(
        self: *@This(),
        node_id: ast.NodeId,
        field_access: *const ast.FieldAccess,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const base_type_id = try self.checkNode(
            field_access.base,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const structure_type_id = switch (self.type_store.getType(base_type_id)) {
            .Structure => |id| id,
            else => {
                std.debug.print(
                    "Type Error: Cannot access field {s} on non-structure type {any}\n",
                    .{ field_access.field_name_token.kind.Identifier, self.getType(base_type_id) },
                );
                return TypeError.TypeMismatch;
            },
        };
        const structure_type = self.type_store.structure_types.items[structure_type_id];
        const field_name = field_access.field_name_token.kind.Identifier;
        const field_index = structure_type.field_index_by_name.get(field_name) orelse {
            std.debug.print(
                "Type Error: No field named {s} exists on structure type {s}\n",
                .{ field_name, structure_type.name },
            );
            return TypeError.TypeMismatch;
        };

        return self.recordNodeType(node_id, structure_type.fields[@intCast(field_index)].type_id);
    }

    fn checkBinaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const left_expression_type = try self.checkNode(
            binary_expression.left,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        const right_expression_type = try self.checkNode(
            binary_expression.right,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (typing.getBinaryOperatorRules(&self.type_store, left_expression_type)) |rules_for_left_type| {
            if (rules_for_left_type.get(binary_expression.operator)) |operator_rule| {
                if (operator_rule.argument_type_id != right_expression_type) {
                    std.debug.print(
                        "Type Error: Binary operator {any} expected right operand of type {any}, got {any}\n",
                        .{
                            binary_expression.operator,
                            self.getType(operator_rule.argument_type_id),
                            self.getType(right_expression_type),
                        },
                    );
                    return TypeError.TypeMismatch;
                }
                return self.recordNodeType(node_id, operator_rule.return_type_id);
            } else {
                std.debug.print(
                    "Type Error: Binary operator {any} is not supported for left operand type {any}\n",
                    .{ binary_expression.operator, self.getType(left_expression_type) },
                );
                return TypeError.TypeMismatch;
            }
        } else {
            std.debug.print(
                "Type Error: No binary operator rules exist for left operand type {any}\n",
                .{self.getType(left_expression_type)},
            );
            return TypeError.TypeMismatch;
        }
    }

    fn checkUnaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        unary_expression: *const ast.UnaryExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const operand_type = try self.checkNode(
            unary_expression.operand,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (typing.getUnaryOperatorRules(&self.type_store, operand_type)) |rules_for_operand_type| {
            if (rules_for_operand_type.get(unary_expression.operator)) |operator_rule| {
                return self.recordNodeType(node_id, operator_rule.return_type_id);
            } else {
                std.debug.print(
                    "Type Error: Unary operator {any} is not supported for operand type {any}\n",
                    .{ unary_expression.operator, self.getType(operand_type) },
                );
                return TypeError.TypeMismatch;
            }
        } else {
            std.debug.print(
                "Type Error: No unary operator rules exist for operand type {any}\n",
                .{self.getType(operand_type)},
            );
            return TypeError.TypeMismatch;
        }
    }

    fn checkBlockNode(
        self: *@This(),
        node_id: ast.NodeId,
        block: *const ast.Block,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.TypeId {
        if (context == .Expression and block.result == null) {
            std.debug.print("Type Error: Block must produce a value in this context\n", .{});
            return TypeError.BlockMustProduceValue;
        }
        if (context == .Statement and block.result != null) {
            std.debug.print("Type Error: Block cannot have a trailing expression in statement context\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        for (block.statements) |*statement| {
            _ = try self.checkNode(
                statement,
                resolved_program,
                exit_behavior_by_node_id,
                .Statement,
            );
        }
        if (block.result) |result_node| {
            const result_type = try self.checkNode(
                result_node,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
            return self.recordNodeType(node_id, result_type);
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkIntegerLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.integer_type_id);
    }

    fn checkBooleanLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.boolean_type_id);
    }

    fn checkStringLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.string_type_id);
    }

    fn checkIdentifierNode(
        self: *@This(),
        node_id: ast.NodeId,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!typing.TypeId {
        const symbol_id = resolved_program.symbol_id_by_node_id.get(node_id).?;
        const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
        return self.recordNodeType(node_id, symbol_type);
    }

    fn checkIfStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_statement: *const ast.IfStatement,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkNode(
            if_statement.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (if_condition_type != self.type_store.boolean_type_id) {
            std.debug.print(
                "Type Error: If condition must be of type boolean, got {any}\n",
                .{self.getType(if_condition_type)},
            );
            return TypeError.TypeMismatch;
        }

        _ = try self.checkNode(
            if_statement.then_branch,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkIfExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_expression: *const ast.IfExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkNode(
            if_expression.condition,
            resolved_program,
            exit_behavior_by_node_id,
            .Expression,
        );
        if (if_condition_type != self.type_store.boolean_type_id) {
            std.debug.print(
                "Type Error: If condition must be of type boolean, got {any}\n",
                .{self.getType(if_condition_type)},
            );
            return TypeError.TypeMismatch;
        }

        const then_block_type = try self.checkNode(
            if_expression.then_block,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        const else_block_type = try self.checkNode(
            if_expression.else_block,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        if (then_block_type != else_block_type) {
            std.debug.print(
                "Type Error: Then and else blocks of an if expression must have the same type, got then: {any}, else: {any}\n",
                .{ self.getType(then_block_type), self.getType(else_block_type) },
            );
            return TypeError.TypeMismatch;
        }

        return self.recordNodeType(node_id, then_block_type);
    }

    fn checkMatchExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        match_expression: *const ast.MatchExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.TypeId {
        const match_type = try self.checkMatchExpression(
            match_expression,
            resolved_program,
            exit_behavior_by_node_id,
            context,
        );
        return self.recordNodeType(node_id, match_type);
    }

    fn checkExpressionStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        expression_statement: *const ast.ExpressionStatement,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!typing.TypeId {
        const expression_type = try self.checkNode(
            expression_statement.expression,
            resolved_program,
            exit_behavior_by_node_id,
            .Statement,
        );
        if (expression_type != self.type_store.unit_type_id) {
            std.debug.print("Type Error: Expression statement must evaluate to unit\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkFunctionDefinitionReturnValue(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!void {
        const symbol_id = resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const resolved_function = self.getResolvedFunction(symbol_id, resolved_program);
        const function_return_type = self.resolveTypeReference(resolved_function.return_type_reference);

        const body_expression_type = try self.checkNode(
            function_definition.body_expression,
            resolved_program,
            exit_behavior_by_node_id,
            .FunctionBody,
        );
        try self.checkReturnStatementsMatchType(
            function_definition.body_expression,
            function_return_type,
            resolved_program,
        );
        self.type_by_symbol_id.put(symbol_id, function_return_type) catch unreachable;

        const body_exit_behavior = exit_behavior_by_node_id.get(
            function_definition.body_expression.id,
        ) orelse unreachable;
        switch (body_exit_behavior) {
            // This is okay, all control flow paths return and we validated that all return statements return the correct type
            .Terminates => {},
            .FallsThroughWithoutValue => {
                if (function_return_type != self.type_store.unit_type_id) {
                    std.debug.print(
                        "Type Error: Function with non-unit return type {any} has control flow path that falls through without returning a value\n",
                        .{self.getType(function_return_type)},
                    );
                    return TypeError.TypeMismatch;
                }
            },
            .FallsThroughWithValue => {
                if (function_return_type != body_expression_type) {
                    std.debug.print(
                        "Type Error: Function with return type {any} has control flow path that falls through with value of type {any}\n",
                        .{ self.getType(function_return_type), self.getType(body_expression_type) },
                    );
                    return TypeError.TypeMismatch;
                }
            },
        }
    }

    fn checkFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!void {
        const function_symbol_id = resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const resolved_function = self.getResolvedFunction(function_symbol_id, resolved_program);
        for (resolved_function.parameters) |parameter| {
            const parameter_type = self.resolveTypeReference(parameter.type_reference);
            self.type_by_symbol_id.put(parameter.symbol_id, parameter_type) catch unreachable;
        }

        try self.checkFunctionDefinitionReturnValue(
            function_node_id,
            function_definition,
            resolved_program,
            exit_behavior_by_node_id,
        );
    }

    fn checkReturnStatementsMatchType(
        self: *@This(),
        node: *const ast.Node,
        function_return_type: typing.TypeId,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        switch (node.kind) {
            .Return => |return_statement| {
                if (return_statement.value) |return_value| {
                    const return_value_type = self.type_by_node_id.get(return_value.id).?;
                    if (return_value_type != function_return_type) {
                        std.debug.print(
                            "Type Error: Return statement in function with return type {any} has return value of type {any}\n",
                            .{ self.getType(function_return_type), self.getType(return_value_type) },
                        );
                        return TypeError.TypeMismatch;
                    }
                } else {
                    if (function_return_type != self.type_store.unit_type_id) {
                        std.debug.print(
                            "Type Error: Return statement with no value in function with non-unit return type {any}\n",
                            .{self.getType(function_return_type)},
                        );
                        return TypeError.TypeMismatch;
                    }
                }
            },
            .IfStatement => |if_statement| {
                try self.checkReturnStatementsMatchType(if_statement.then_branch, function_return_type, resolved_program);
            },
            .IfExpression => |if_expression| {
                try self.checkReturnStatementsMatchType(if_expression.then_block, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(if_expression.else_block, function_return_type, resolved_program);
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    try self.checkReturnStatementsMatchType(subject, function_return_type, resolved_program);
                }
                for (match_expression.arms) |arm| {
                    try self.checkReturnStatementsMatchType(arm.pattern_or_condition, function_return_type, resolved_program);
                    try self.checkReturnStatementsMatchType(arm.body, function_return_type, resolved_program);
                }
                if (match_expression.else_arm) |else_arm| {
                    try self.checkReturnStatementsMatchType(else_arm, function_return_type, resolved_program);
                }
            },
            .Block => |block| {
                for (block.statements) |*statement| {
                    try self.checkReturnStatementsMatchType(statement, function_return_type, resolved_program);
                }
                if (block.result) |result_node| {
                    try self.checkReturnStatementsMatchType(result_node, function_return_type, resolved_program);
                }
            },
            .Loop => |loop| {
                try self.checkReturnStatementsMatchType(loop.body_block, function_return_type, resolved_program);
            },
            .While => |while_statement| {
                try self.checkReturnStatementsMatchType(while_statement.body_block, function_return_type, resolved_program);
            },
            .CallExpression => |call_expression| {
                try self.checkReturnStatementsMatchType(call_expression.callee, function_return_type, resolved_program);
                for (call_expression.arguments) |*argument| {
                    try self.checkReturnStatementsMatchType(argument, function_return_type, resolved_program);
                }
            },
            .Assignment => |assignment| {
                try self.checkReturnStatementsMatchType(assignment.target, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(assignment.value, function_return_type, resolved_program);
            },
            .Declaration => |declaration| {
                try self.checkReturnStatementsMatchType(declaration.value, function_return_type, resolved_program);
            },
            .ExpressionStatement => |expression_statement| {
                try self.checkReturnStatementsMatchType(expression_statement.expression, function_return_type, resolved_program);
            },
            .BinaryExpression => |binary_expression| {
                try self.checkReturnStatementsMatchType(binary_expression.left, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(binary_expression.right, function_return_type, resolved_program);
            },
            .UnaryExpression => |unary_expression| {
                try self.checkReturnStatementsMatchType(unary_expression.operand, function_return_type, resolved_program);
            },
            .FieldAccess => |field_access| {
                try self.checkReturnStatementsMatchType(field_access.base, function_return_type, resolved_program);
            },
            .StructureConstruction => |structure_construction| {
                for (structure_construction.fields) |field| {
                    try self.checkReturnStatementsMatchType(field.value, function_return_type, resolved_program);
                }
            },
            .ItemDefinition => {},
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .Leave,
            .Continue,
            => {},
        }
    }

    fn resolveTypeAnnotation(
        self: *const @This(),
        type_annotation: ast.TypeAnnotation,
        resolved_program: *const symbols.ResolvedProgram,
    ) typing.TypeId {
        const type_reference = resolved_program.type_reference_by_type_annotation_id.get(type_annotation.id) orelse unreachable;
        return self.resolveTypeReference(type_reference);
    }

    fn resolveTypeReference(
        self: *const @This(),
        type_reference: symbols.ResolvedTypeReference,
    ) typing.TypeId {
        return switch (type_reference) {
            .Builtin => |builtin| switch (builtin) {
                .Unit => self.type_store.unit_type_id,
                .Boolean => self.type_store.boolean_type_id,
                .Integer => self.type_store.integer_type_id,
                .String => self.type_store.string_type_id,
            },
            .Symbol => |symbol_id| self.type_by_symbol_id.get(symbol_id) orelse unreachable,
        };
    }

    fn getResolvedFunction(
        self: *const @This(),
        function_symbol_id: symbols.SymbolId,
        resolved_program: *const symbols.ResolvedProgram,
    ) symbols.ResolvedFunction {
        _ = self;
        return switch (resolved_program.resolved_item_by_symbol_id.get(function_symbol_id) orelse unreachable) {
            .Function => |function| function,
            else => unreachable,
        };
    }

    fn checkMatchExpression(
        self: *@This(),
        match_expression: *const ast.MatchExpression,
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        context: ValidationContext,
    ) TypeError!typing.TypeId {
        const exhaustiveness_class: ExhaustivenessClass = if (match_expression.subject) |subject| class: {
            const subject_type = try self.checkNode(
                subject,
                resolved_program,
                exit_behavior_by_node_id,
                .Expression,
            );
            break :class switch (self.getType(subject_type)) {
                .Boolean => .Boolean,
                .Integer => .IntegerOpen,
                else => {
                    std.debug.print("Type Error: Match subject must be boolean or integer in v1, got {any}\n", .{self.getType(subject_type)});
                    return TypeError.TypeMismatch;
                },
            };
        } else .Subjectless;

        var saw_true = false;
        var saw_false = false;
        var integer_patterns = std.AutoHashMap(i64, void).init(self.allocator);
        defer integer_patterns.deinit();

        var arm_result_type: ?typing.TypeId = null;
        for (match_expression.arms) |arm| {
            switch (exhaustiveness_class) {
                .Subjectless => {
                    const condition_type = try self.checkNode(
                        arm.pattern_or_condition,
                        resolved_program,
                        exit_behavior_by_node_id,
                        .Expression,
                    );
                    if (condition_type != self.type_store.boolean_type_id) {
                        std.debug.print("Type Error: Subjectless match arm condition must be boolean, got {any}\n", .{self.getType(condition_type)});
                        return TypeError.TypeMismatch;
                    }
                },
                .Boolean => switch (arm.pattern_or_condition.kind) {
                    .BooleanLiteral => |token| {
                        if (token.kind.BooleanLiteral) {
                            if (saw_true) return TypeError.DuplicateMatchArm;
                            saw_true = true;
                        } else {
                            if (saw_false) return TypeError.DuplicateMatchArm;
                            saw_false = true;
                        }
                        self.type_by_node_id.put(arm.pattern_or_condition.id, self.type_store.boolean_type_id) catch unreachable;
                    },
                    else => {
                        std.debug.print("Type Error: Boolean match arms must use boolean literals in v1\n", .{});
                        return TypeError.TypeMismatch;
                    },
                },
                .IntegerOpen => switch (arm.pattern_or_condition.kind) {
                    .IntegerLiteral => |token| {
                        _ = try self.checkNode(
                            arm.pattern_or_condition,
                            resolved_program,
                            exit_behavior_by_node_id,
                            .Expression,
                        );
                        const value = token.kind.IntLiteral;
                        if (integer_patterns.contains(value)) {
                            return TypeError.DuplicateMatchArm;
                        }
                        integer_patterns.put(value, {}) catch unreachable;
                    },
                    else => {
                        const pattern_type = try self.checkNode(
                            arm.pattern_or_condition,
                            resolved_program,
                            exit_behavior_by_node_id,
                            .Expression,
                        );
                        if (pattern_type != self.type_store.integer_type_id) {
                            std.debug.print("Type Error: Integer match arms must be integer expressions in v1\n", .{});
                            return TypeError.TypeMismatch;
                        }
                    },
                },
            }

            const body_type = try self.checkNode(
                arm.body,
                resolved_program,
                exit_behavior_by_node_id,
                context,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != body_type) {
                    std.debug.print(
                        "Type Error: Match arms must all produce the same type, expected {any}, got {any}\n",
                        .{ self.getType(expected_type), self.getType(body_type) },
                    );
                    return TypeError.TypeMismatch;
                }
            } else {
                arm_result_type = body_type;
            }
        }

        if (match_expression.else_arm) |else_arm| {
            const else_type = try self.checkNode(
                else_arm,
                resolved_program,
                exit_behavior_by_node_id,
                context,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != else_type) {
                    std.debug.print(
                        "Type Error: Match else arm must produce the same type as other arms, expected {any}, got {any}\n",
                        .{ self.getType(expected_type), self.getType(else_type) },
                    );
                    return TypeError.TypeMismatch;
                }
            } else {
                arm_result_type = else_type;
            }
        }

        const is_exhaustive = switch (exhaustiveness_class) {
            .Subjectless => match_expression.else_arm != null,
            .Boolean => (saw_true and saw_false) or match_expression.else_arm != null,
            .IntegerOpen => match_expression.else_arm != null,
        };
        if (!is_exhaustive) {
            std.debug.print("Type Error: Match expression is not exhaustive in v1\n", .{});
            return TypeError.NonExhaustiveMatch;
        }

        const result_type = arm_result_type orelse self.type_store.unit_type_id;
        if (context == .Statement and result_type != self.type_store.unit_type_id) {
            std.debug.print("Type Error: Match expression used as statement must evaluate to unit\n", .{});
            return TypeError.BlockCannotProduceValue;
        }

        return result_type;
    }

    fn recordNodeType(
        self: *@This(),
        node_id: ast.NodeId,
        node_type: typing.TypeId,
    ) typing.TypeId {
        self.type_by_node_id.put(node_id, node_type) catch unreachable;
        return node_type;
    }

    fn getType(self: *const @This(), type_id: typing.TypeId) typing.Type {
        return self.type_store.getType(type_id);
    }
};
