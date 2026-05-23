const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");
const type_checking_types = @import("type_checking_types.zig");

pub const TypeError = type_checking_types.TypeError;
const ValidationContext = type_checking_types.ValidationContext;
const ExhaustivenessClass = type_checking_types.ExhaustivenessClass;
const TypeCheckEnvironment = type_checking_types.TypeCheckEnvironment;
const PlaceInfo = type_checking_types.PlaceInfo;
const TypeCheckResult = type_checking_types.TypeCheckResult;

pub const NodeTypeAnalyzer = struct {
    allocator: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    type_store: typing.TypeStore,
    type_by_symbol_id: typing.TypeBySymbolId,
    type_by_node_id: typing.TypeByNodeId,
    structure_construction_layout_by_node_id: typing.StructureConstructionLayoutByNodeId,
    member_access_by_node_id: typing.MemberAccessByNodeId,

    pub fn init(allocator: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{
            .allocator = allocator,
            .diagnostic_store = diagnostic_store,
            .type_store = typing.TypeStore.init(allocator),
            .type_by_symbol_id = typing.TypeBySymbolId.init(allocator),
            .type_by_node_id = typing.TypeByNodeId.init(allocator),
            .structure_construction_layout_by_node_id = typing.StructureConstructionLayoutByNodeId.init(allocator),
            .member_access_by_node_id = typing.MemberAccessByNodeId.init(allocator),
        };
    }

    pub fn resetState(self: *@This()) void {
        self.type_store = typing.TypeStore.init(self.allocator);
        self.type_by_symbol_id = typing.TypeBySymbolId.init(self.allocator);
        self.type_by_node_id = typing.TypeByNodeId.init(self.allocator);
        self.structure_construction_layout_by_node_id = typing.StructureConstructionLayoutByNodeId.init(self.allocator);
        self.member_access_by_node_id = typing.MemberAccessByNodeId.init(self.allocator);
    }

    pub fn analyzeProgram(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!void {
        const root_environment = TypeCheckEnvironment{
            .resolved_program = resolved_program,
            .exit_behavior_by_node_id = exit_behavior_by_node_id,
            .context = .Statement,
            .contextual_type_id = null,
        };

        for (resolved_program.program.statements) |*statement| {
            _ = try self.checkNode(statement, root_environment);
        }
    }

    pub fn typeCheckResult(self: *const @This()) TypeCheckResult {
        return .{
            .type_store = self.type_store,
            .type_by_symbol_id = self.type_by_symbol_id,
            .type_by_node_id = self.type_by_node_id,
            .structure_construction_layout_by_node_id = self.structure_construction_layout_by_node_id,
            .member_access_by_node_id = self.member_access_by_node_id,
        };
    }

    fn typeName(self: *@This(), type_id: typing.TypeId) ![]const u8 {
        return self.type_store.getType(type_id).name(&self.type_store, self.allocator);
    }

    fn checkNode(
        self: *@This(),
        node: *const ast.Node,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        switch (node.kind) {
            .Declaration => |declaration| return self.checkDeclarationNode(node.id, &declaration, environment),
            .ItemDefinition => |item_definition| return self.checkItemDefinitionNode(node.id, &item_definition, environment),
            .Return => |return_statement| return self.checkReturnNode(node.id, &return_statement, environment),
            .Assignment => |assignment| return self.checkAssignmentNode(node.id, &assignment, environment),
            .Loop => |loop| return self.checkLoopNode(node.id, &loop, environment),
            .While => |while_statement| return self.checkWhileNode(node.id, &while_statement, environment),
            .ForIn => |for_in| return self.checkForInNode(node.id, &for_in, environment),
            .Leave => return self.checkLeaveNode(node.id),
            .Continue => return self.checkContinueNode(node.id),
            .CallExpression => |call_expression| return self.checkCallExpressionNode(node.id, &call_expression, environment),
            .MemberAccess => |member_access| return self.checkMemberAccessNode(node.id, &member_access, environment),
            .BinaryExpression => |binary_expression| return self.checkBinaryExpressionNode(node.id, &binary_expression, environment),
            .UnaryExpression => |unary_expression| return self.checkUnaryExpressionNode(node.id, &unary_expression, environment),
            .StructureConstruction => |structure_construction| return self.checkStructureConstructionNode(node.id, &structure_construction, environment),
            .AnonymousStructureLiteral => |anonymous_structure_literal| return self.checkAnonymousStructureLiteralNode(node.id, &anonymous_structure_literal, environment),
            .Block => |block| return self.checkBlockNode(node.id, &block, environment),
            .IntegerLiteral => return self.checkIntegerLiteralNode(node.id),
            .BooleanLiteral => return self.checkBooleanLiteralNode(node.id),
            .StringLiteral => return self.checkStringLiteralNode(node.id),
            .UnitLiteral => return self.checkUnitLiteralNode(node.id),
            .Identifier => return self.checkIdentifierNode(node.id, environment),
            .IfStatement => |if_statement| return self.checkIfStatementNode(node.id, &if_statement, environment),
            .IfExpression => |if_expression| return self.checkIfExpressionNode(node.id, &if_expression, environment),
            .MatchExpression => |match_expression| return self.checkMatchExpressionNode(node.id, &match_expression, environment),
            .ExpressionStatement => |expression_statement| return self.checkExpressionStatementNode(node.id, &expression_statement, environment),
            .ArrayLiteral => |array_literal| return self.checkArrayLiteralNode(node.id, &array_literal, environment),
            .IndexAccess => |index_access| return self.checkIndexAccessNode(node.id, &index_access, environment),
        }
    }

    fn checkExpression(
        self: *@This(),
        node: *const ast.Node,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        return self.checkNode(node, environment.withContextAndType(.Expression, null));
    }

    fn checkStatement(
        self: *@This(),
        node: *const ast.Node,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        return self.checkNode(node, environment.withContext(.Statement));
    }

    fn checkWithExpectedType(
        self: *@This(),
        node: *const ast.Node,
        expected_type: typing.TypeId,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        return self.checkNode(node, environment.withContextAndType(.Expression, expected_type));
    }

    fn checkItemDefinitionNode(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: *const ast.ItemDefinition,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        switch (item_definition.item) {
            .Function => |function_definition| try self.checkFunctionDefinition(
                node_id,
                &function_definition,
                environment,
            ),
            .Structure => |structure_definition| {
                for (structure_definition.function_definitions) |*function_definition_node| {
                    const method_definition = switch (function_definition_node.kind) {
                        .ItemDefinition => |method_item_definition| switch (method_item_definition.item) {
                            .Function => |function| function,
                            else => unreachable,
                        },
                        else => unreachable,
                    };
                    try self.checkFunctionDefinition(
                        function_definition_node.id,
                        &method_definition,
                        environment,
                    );
                }
            },
        }
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkStructureConstructionNode(
        self: *@This(),
        node_id: ast.NodeId,
        structure_construction: *const ast.StructureConstruction,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const structure_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const type_id = self.type_by_symbol_id.get(structure_symbol_id).?;
        return self.checkStructureLiteralFieldsAgainstType(
            node_id,
            structure_construction.fields,
            type_id,
            environment,
        );
    }

    fn checkAnonymousStructureLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
        anonymous_structure_literal: *const ast.AnonymousStructureLiteral,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const type_id = environment.contextual_type_id orelse {
            try self.diagnostic_store.emitErrorFromToken(
                anonymous_structure_literal.dot_token,
                "cannot infer the type of an anonymous structure literal without a contextual type",
            );
            return error.DiagnosticsEmitted;
        };
        return self.checkStructureLiteralFieldsAgainstType(
            node_id,
            anonymous_structure_literal.fields,
            type_id,
            environment,
        );
    }

    fn checkStructureLiteralFieldsAgainstType(
        self: *@This(),
        node_id: ast.NodeId,
        fields: []const ast.StructureConstructionField,
        type_id: typing.TypeId,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const structure_literal_type = self.type_store.getType(type_id);
        const structure_type_id = switch (structure_literal_type) {
            .Structure => |id| id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, fields[0].name, "expected a structure type for this literal, found {s}", .{try self.typeName(type_id)});
                return error.DiagnosticsEmitted;
            },
        };
        const structure_type = self.type_store.structure_types.items[structure_type_id];

        var unique_field_names = std.StringHashMap(bool).init(self.allocator);
        defer unique_field_names.deinit();
        var field_indices = std.ArrayList(u32){};
        defer field_indices.deinit(self.allocator);

        for (fields) |field| {
            const field_name = field.name.kind.Identifier;
            const existing_field_name = unique_field_names.get(field_name);
            if (existing_field_name) |_| {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, field.name, "duplicate field '{s}' in structure construction", .{field_name});
                return error.DiagnosticsEmitted;
            }
            unique_field_names.put(field_name, true) catch unreachable;

            const field_index = structure_type.field_index_by_name.get(field_name) orelse {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, field.name, "field '{s}' does not exist on structure '{s}'", .{ field_name, structure_type.name });
                return error.DiagnosticsEmitted;
            };
            const structure_type_field = structure_type.fields[@intCast(field_index)];
            const field_environment = environment.withContextAndType(.Expression, structure_type_field.type_id);
            const field_value_type_id = try self.checkNode(field.value, field_environment);

            if (structure_type_field.type_id != field_value_type_id) {
                try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    field.name,
                    "field '{s}' on structure '{s}' expects {s}, found {s}",
                    .{ field_name, structure_type.name, try self.typeName(structure_type_field.type_id), try self.typeName(field_value_type_id) },
                );
                return error.DiagnosticsEmitted;
            }

            field_indices.append(self.allocator, field_index) catch unreachable;
        }

        for (structure_type.fields) |field| {
            const field_exists_in_construction = unique_field_names.get(field.name);
            if (field_exists_in_construction == null) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, fields[0].name, "missing field '{s}' in construction of '{s}'", .{ field.name, structure_type.name });
                return error.DiagnosticsEmitted;
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
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const annotated_type = if (environment.resolved_program.annotated_type_reference_by_symbol_id.get(symbol_id)) |type_reference|
            self.resolveTypeReference(type_reference)
        else
            null;
        const value_environment = environment.withContextAndType(.Expression, annotated_type);
        const value_type = try self.checkNode(declaration.value, value_environment);
        if (annotated_type) |annotated| {
            if (annotated != value_type) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, declaration.name, "declaration '{s}' expects {s}, found {s}", .{ declaration.name.kind.Identifier, try self.typeName(annotated), try self.typeName(value_type) });
                return error.DiagnosticsEmitted;
            }
        }

        self.type_by_symbol_id.put(symbol_id, value_type) catch unreachable;
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkReturnNode(
        self: *@This(),
        node_id: ast.NodeId,
        return_statement: *const ast.Return,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        if (return_statement.value) |return_value| {
            const return_environment = environment.withContext(.Expression);
            _ = try self.checkNode(return_value, return_environment);
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkAssignmentNode(
        self: *@This(),
        node_id: ast.NodeId,
        assignment: *const ast.Assignment,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const place = try self.checkPlaceNode(assignment.target, environment);
        const value_environment = environment.withContextAndType(.Expression, place.type_id);
        const value_type = try self.checkNode(assignment.value, value_environment);

        switch (assignment.operator) {
            .Assign => {
                if (place.type_id != value_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, assignment.assignment_token, "cannot assign value of type {s} to target of type {s}", .{ try self.typeName(value_type), try self.typeName(place.type_id) });
                    return error.DiagnosticsEmitted;
                }
            },
            .Compound => |binary_operator| {
                const compound_result_type = try self.checkBinaryOperatorApplication(
                    assignment.assignment_token,
                    binary_operator,
                    place.type_id,
                    value_type,
                );
                if (compound_result_type != place.type_id) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, assignment.assignment_token, "compound assignment produces {s}, which cannot be assigned to target of type {s}", .{ try self.typeName(compound_result_type), try self.typeName(place.type_id) });
                    return error.DiagnosticsEmitted;
                }
            },
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkPlaceNode(
        self: *@This(),
        node: *const ast.Node,
        environment: TypeCheckEnvironment,
    ) TypeError!PlaceInfo {
        switch (node.kind) {
            .Identifier => |identifier| {
                const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node.id) orelse unreachable;
                const symbol = environment.resolved_program.symbol_table.getSymbol(symbol_id);
                switch (symbol.kind) {
                    .Binding => |binding| {
                        if (binding.binding_mutability == symbols.BindingMutability.Immutable) {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, identifier, "cannot assign to immutable binding '{s}'", .{identifier.kind.Identifier});
                            return error.DiagnosticsEmitted;
                        }
                    },
                    else => {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, identifier, "cannot assign to non-binding symbol '{s}'", .{identifier.kind.Identifier});
                        return error.DiagnosticsEmitted;
                    },
                }

                const type_id = try self.checkNode(node, environment.withContextAndType(.Expression, null));
                return .{ .type_id = type_id };
            },
            .MemberAccess => {
                const type_id = try self.checkNode(node, environment.withContextAndType(.Expression, null));
                const member_access = self.member_access_by_node_id.get(node.id) orelse unreachable;
                return switch (member_access) {
                    .StructureInstanceFieldAccess => .{ .type_id = type_id },
                    .StructureInstanceMethodAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to a structure instance method");
                        return error.DiagnosticsEmitted;
                    },
                    .ArrayInstanceFieldAccess => |array_field| switch (array_field) {
                        .Length => {
                            try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to read-only array member 'length'");
                            return error.DiagnosticsEmitted;
                        },
                    },
                    .StructureTypeFunctionAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to a structure function");
                        return error.DiagnosticsEmitted;
                    },
                    .ArrayInstanceMethodAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to an array instance method");
                        return error.DiagnosticsEmitted;
                    },
                    .StringInstanceFieldAccess => |string_field| switch (string_field) {
                        .Length => {
                            try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to read-only string member 'length'");
                            return error.DiagnosticsEmitted;
                        },
                    },
                    .StringInstanceMethodAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to a string instance method");
                        return error.DiagnosticsEmitted;
                    },
                    .IntegerInstanceMethodAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to an integer instance method");
                        return error.DiagnosticsEmitted;
                    },
                };
            },
            .IndexAccess => {
                const type_id = try self.checkNode(node, environment.withContextAndType(.Expression, null));
                return .{ .type_id = type_id };
            },
            else => {
                try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "invalid assignment target");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn checkLoopNode(
        self: *@This(),
        node_id: ast.NodeId,
        loop: *const ast.Loop,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const body_environment = environment.withContext(.Statement);
        _ = try self.checkNode(loop.body_block, body_environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkWhileNode(
        self: *@This(),
        node_id: ast.NodeId,
        while_statement: *const ast.While,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const while_condition_type = try self.checkExpression(while_statement.condition, environment);
        if (while_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, while_statement.while_token, "while condition must be boolean, found {s}", .{try self.typeName(while_condition_type)});
            return error.DiagnosticsEmitted;
        }

        if (while_statement.update) |update| {
            _ = try self.checkStatement(update, environment);
        }

        _ = try self.checkStatement(while_statement.body_block, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkForInNode(
        self: *@This(),
        node_id: ast.NodeId,
        for_in: *const ast.ForIn,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const iterable_type_id = try self.checkExpression(for_in.iterable, environment);
        const item_type_id = switch (self.type_store.getType(iterable_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, for_in.in_token, "for-in iterable must be an array, found {s}", .{try self.typeName(iterable_type_id)});
                return error.DiagnosticsEmitted;
            },
        };

        const item_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        self.type_by_symbol_id.put(item_symbol_id, item_type_id) catch unreachable;

        _ = try self.checkStatement(for_in.body_block, environment);
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
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const callee_type_id = try self.checkExpression(call_expression.callee, environment);

        const function_type_id = switch (self.type_store.getType(callee_type_id)) {
            .Function => |function_type_id| function_type_id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, call_expression.left_parenthesis, "cannot call value of non-function type {s}", .{try self.typeName(callee_type_id)});
                return error.DiagnosticsEmitted;
            },
        };
        const function_type = self.type_store.function_types.items[function_type_id];

        if (call_expression.arguments.len != function_type.parameter_types.len) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, call_expression.left_parenthesis, "function expects {d} arguments, found {d}", .{ function_type.parameter_types.len, call_expression.arguments.len });
            return error.DiagnosticsEmitted;
        }

        for (call_expression.arguments, function_type.parameter_types) |*argument, parameter_type| {
            const argument_type = try self.checkWithExpectedType(argument, parameter_type, environment);
            if (argument_type != parameter_type) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, argument.primaryToken(), "function argument expects {s}, found {s}", .{ try self.typeName(parameter_type), try self.typeName(argument_type) });
                return error.DiagnosticsEmitted;
            }
        }

        return self.recordNodeType(node_id, function_type.return_type);
    }

    fn checkMemberAccessNode(
        self: *@This(),
        node_id: ast.NodeId,
        member_access: *const ast.MemberAccess,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const member_name = member_access.member_name_token.kind.Identifier;
        if (member_access.base.kind == .Identifier) {
            const base_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(member_access.base.id) orelse unreachable;
            const base_symbol = environment.resolved_program.symbol_table.getSymbol(base_symbol_id);
            switch (base_symbol.kind) {
                .Structure => {
                    const base_type_id = self.type_by_symbol_id.get(base_symbol_id) orelse unreachable;
                    const structure_type_id = switch (self.type_store.getType(base_type_id)) {
                        .Structure => |structure_type_id| structure_type_id,
                        else => unreachable,
                    };
                    const structure_type = self.type_store.structure_types.items[structure_type_id];
                    const function_symbol_id = structure_type.function_symbol_id_by_name.get(member_name) orelse {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "no function named '{s}' exists on structure type '{s}'", .{ member_name, structure_type.name });
                        return error.DiagnosticsEmitted;
                    };

                    self.recordMemberAccess(node_id, .{ .StructureTypeFunctionAccess = .{
                        .structure_symbol_id = base_symbol_id,
                        .function_symbol_id = function_symbol_id,
                    } });
                    const function_type_id = self.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
                    return self.recordNodeType(node_id, function_type_id);
                },
                .Binding => return self.checkInstanceMemberAccessNode(
                    node_id,
                    member_access,
                    environment,
                ),
                .Function => {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "cannot access member '{s}' on a function", .{member_name});
                    return error.DiagnosticsEmitted;
                },
            }
        }

        return self.checkInstanceMemberAccessNode(
            node_id,
            member_access,
            environment,
        );
    }

    fn checkInstanceMemberAccessNode(
        self: *@This(),
        node_id: ast.NodeId,
        member_access: *const ast.MemberAccess,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const member_name = member_access.member_name_token.kind.Identifier;
        const base_type_id = try self.checkNode(
            member_access.base,
            environment.withContextAndType(.Expression, null),
        );
        switch (self.type_store.getType(base_type_id)) {
            .Structure => |structure_type_id| {
                const structure_type = self.type_store.structure_types.items[structure_type_id];
                const field_index = structure_type.field_index_by_name.get(member_name);
                if (field_index) |structure_field_index| {
                    self.recordMemberAccess(node_id, .{ .StructureInstanceFieldAccess = .{ .field_index = structure_field_index } });
                    return self.recordNodeType(node_id, structure_type.fields[@intCast(structure_field_index)].type_id);
                }

                const function_symbol_id = structure_type.function_symbol_id_by_name.get(member_name);
                if (function_symbol_id) |structure_function_symbol_id| {
                    // Instance method access binds the receiver and drops the `self` parameter from the callable type.
                    const bound_function_type_id = try self.bindInstanceMethodFunctionType(
                        member_access.member_name_token,
                        structure_function_symbol_id,
                        base_type_id,
                    );
                    self.recordMemberAccess(node_id, .{ .StructureInstanceMethodAccess = .{
                        .structure_symbol_id = structure_type.symbol_id,
                        .function_symbol_id = structure_function_symbol_id,
                    } });
                    return self.recordNodeType(node_id, bound_function_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "type '{s}' has no member named '{s}'", .{ structure_type.name, member_name });
                return error.DiagnosticsEmitted;
            },
            .Array => {
                if (std.mem.eql(u8, member_name, "append")) {
                    // Array append mutates the shared array header and only needs the appended element explicitly.
                    const append_function_type_id = try self.getArrayAppendFunctionTypeId(base_type_id);
                    self.recordMemberAccess(node_id, .{ .ArrayInstanceMethodAccess = .Append });
                    return self.recordNodeType(node_id, append_function_type_id);
                }
                if (std.mem.eql(u8, member_name, "length")) {
                    self.recordMemberAccess(node_id, .{ .ArrayInstanceFieldAccess = .Length });
                    return self.recordNodeType(node_id, self.type_store.integer_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "array has no member named '{s}'", .{member_name});
                return error.DiagnosticsEmitted;
            },
            .String => {
                if (std.mem.eql(u8, member_name, "length")) {
                    self.recordMemberAccess(node_id, .{ .StringInstanceFieldAccess = .Length });
                    return self.recordNodeType(node_id, self.type_store.integer_type_id);
                }
                if (std.mem.eql(u8, member_name, "trim")) {
                    const trim_function_type_id = self.getStringMethodFunctionTypeId(&.{}, self.type_store.string_type_id);
                    self.recordMemberAccess(node_id, .{ .StringInstanceMethodAccess = .Trim });
                    return self.recordNodeType(node_id, trim_function_type_id);
                }
                if (std.mem.eql(u8, member_name, "split")) {
                    const split_function_type_id = self.getStringMethodFunctionTypeId(
                        &.{self.type_store.string_type_id},
                        self.type_store.getOrCreateArrayType(self.type_store.string_type_id),
                    );
                    self.recordMemberAccess(node_id, .{ .StringInstanceMethodAccess = .Split });
                    return self.recordNodeType(node_id, split_function_type_id);
                }
                if (std.mem.eql(u8, member_name, "toInt")) {
                    const to_int_function_type_id = self.getStringMethodFunctionTypeId(&.{}, self.type_store.integer_type_id);
                    self.recordMemberAccess(node_id, .{ .StringInstanceMethodAccess = .ToInt });
                    return self.recordNodeType(node_id, to_int_function_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "string has no member named '{s}'", .{member_name});
                return error.DiagnosticsEmitted;
            },
            .Integer => {
                if (std.mem.eql(u8, member_name, "toString")) {
                    const to_string_function_type_id = self.getStringMethodFunctionTypeId(&.{}, self.type_store.string_type_id);
                    self.recordMemberAccess(node_id, .{ .IntegerInstanceMethodAccess = .ToString });
                    return self.recordNodeType(node_id, to_string_function_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "int has no member named '{s}'", .{member_name});
                return error.DiagnosticsEmitted;
            },
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_access.member_name_token, "cannot access member '{s}' on type {s}", .{ member_name, try self.typeName(base_type_id) });
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn getArrayAppendFunctionTypeId(
        self: *@This(),
        array_type_id: typing.TypeId,
    ) TypeError!typing.TypeId {
        const element_type_id = switch (self.type_store.getType(array_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => unreachable,
        };

        const parameter_types = self.allocator.alloc(typing.TypeId, 1) catch unreachable;
        parameter_types[0] = element_type_id;
        return self.type_store.addFunctionType(.{
            .parameter_types = parameter_types,
            .return_type = self.type_store.unit_type_id,
        });
    }

    fn getStringMethodFunctionTypeId(
        self: *@This(),
        parameter_type_ids: []const typing.TypeId,
        return_type_id: typing.TypeId,
    ) typing.TypeId {
        const parameter_types = self.allocator.alloc(typing.TypeId, parameter_type_ids.len) catch unreachable;
        @memcpy(parameter_types, parameter_type_ids);

        return self.type_store.addFunctionType(.{
            .parameter_types = parameter_types,
            .return_type = return_type_id,
        });
    }

    fn bindInstanceMethodFunctionType(
        self: *@This(),
        member_name_token: lexing.Token,
        function_symbol_id: symbols.SymbolId,
        receiver_type_id: typing.TypeId,
    ) TypeError!typing.TypeId {
        const function_type_id = self.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_type = switch (self.type_store.getType(function_type_id)) {
            .Function => |id| self.type_store.function_types.items[id],
            else => unreachable,
        };

        if (function_type.parameter_types.len == 0) {
            try self.diagnostic_store.emitErrorFromToken(member_name_token, "structure instance method is missing a receiver parameter");
            return error.DiagnosticsEmitted;
        }

        if (function_type.parameter_types[0] != receiver_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_name_token, "structure instance method receiver expects {s}, found {s}", .{ try self.typeName(function_type.parameter_types[0]), try self.typeName(receiver_type_id) });
            return error.DiagnosticsEmitted;
        }

        var remaining_parameter_types = std.ArrayList(typing.TypeId){};
        defer remaining_parameter_types.deinit(self.allocator);
        for (function_type.parameter_types[1..]) |parameter_type_id| {
            remaining_parameter_types.append(self.allocator, parameter_type_id) catch unreachable;
        }

        return self.type_store.addFunctionType(.{
            .parameter_types = remaining_parameter_types.toOwnedSlice(self.allocator) catch unreachable,
            .return_type = function_type.return_type,
        });
    }

    fn checkBinaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const left_expression_type = try self.checkNode(
            binary_expression.left,
            environment.withContextAndType(.Expression, null),
        );
        const right_expression_type = try self.checkNode(
            binary_expression.right,
            environment.withContextAndType(.Expression, null),
        );
        const result_type = try self.checkBinaryOperatorApplication(
            binary_expression.operator_token,
            binary_expression.operator,
            left_expression_type,
            right_expression_type,
        );
        return self.recordNodeType(node_id, result_type);
    }

    fn checkBinaryOperatorApplication(
        self: *@This(),
        operator_token: lexing.Token,
        binary_operator: ast.BinaryOperator,
        left_operand_type: typing.TypeId,
        right_operand_type: typing.TypeId,
    ) TypeError!typing.TypeId {
        if (typing.getBinaryOperatorRules(&self.type_store, left_operand_type)) |rules_for_left_type| {
            if (rules_for_left_type.get(binary_operator)) |operator_rule| {
                if (operator_rule.argument_type_id != right_operand_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(
                        self.allocator,
                        operator_token,
                        "binary operator '{s}' expects right operand of type {s}, found {s}",
                        .{ binary_operator.name(), try self.typeName(operator_rule.argument_type_id), try self.typeName(right_operand_type) },
                    );
                    return error.DiagnosticsEmitted;
                }
                return operator_rule.return_type_id;
            } else {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, operator_token, "binary operator '{s}' is not supported for left operand type {s}", .{ binary_operator.name(), try self.typeName(left_operand_type) });
                return error.DiagnosticsEmitted;
            }
        } else {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, operator_token, "no binary operator rules exist for left operand type {s}", .{try self.typeName(left_operand_type)});
            return error.DiagnosticsEmitted;
        }
    }

    fn checkUnaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        unary_expression: *const ast.UnaryExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const operand_type = try self.checkNode(
            unary_expression.operand,
            environment.withContextAndType(.Expression, null),
        );
        if (typing.getUnaryOperatorRules(&self.type_store, operand_type)) |rules_for_operand_type| {
            if (rules_for_operand_type.get(unary_expression.operator)) |operator_rule| {
                return self.recordNodeType(node_id, operator_rule.return_type_id);
            } else {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, unary_expression.operator_token, "unary operator '{s}' is not supported for operand type {s}", .{ unary_expression.operator.name(), try self.typeName(operand_type) });
                return error.DiagnosticsEmitted;
            }
        } else {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, unary_expression.operator_token, "no unary operator rules exist for operand type {s}", .{try self.typeName(operand_type)});
            return error.DiagnosticsEmitted;
        }
    }

    fn checkBlockNode(
        self: *@This(),
        node_id: ast.NodeId,
        block: *const ast.Block,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const context = environment.context;
        const contextual_type_id = environment.contextual_type_id;
        if (context == .Expression and block.result == null) {
            try self.diagnostic_store.emitErrorFromToken(block.left_brace, "block must produce a value in this context");
            return error.DiagnosticsEmitted;
        }
        if (context == .Statement and block.result != null) {
            try self.diagnostic_store.emitErrorFromToken(block.left_brace, "block cannot have a trailing expression in statement context");
            return error.DiagnosticsEmitted;
        }

        for (block.statements) |*statement| {
            _ = try self.checkNode(statement, environment.withContext(.Statement));
        }
        if (block.result) |result_node| {
            const result_type = try self.checkNode(
                result_node,
                environment.withContextAndType(.Expression, contextual_type_id),
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

    fn checkUnitLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkIdentifierNode(
        self: *@This(),
        node_id: ast.NodeId,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const symbol_type = self.type_by_symbol_id.get(symbol_id).?;
        return self.recordNodeType(node_id, symbol_type);
    }

    fn checkIfStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_statement: *const ast.IfStatement,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkExpression(if_statement.condition, environment);
        if (if_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_statement.if_token, "if condition must be boolean, found {s}", .{try self.typeName(if_condition_type)});
            return error.DiagnosticsEmitted;
        }

        _ = try self.checkStatement(if_statement.then_branch, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkIfExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_expression: *const ast.IfExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkExpression(if_expression.condition, environment);
        if (if_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_expression.if_token, "if condition must be boolean, found {s}", .{try self.typeName(if_condition_type)});
            return error.DiagnosticsEmitted;
        }

        const then_block_type = try self.checkNode(if_expression.then_block, environment);
        const else_block_type = try self.checkNode(if_expression.else_block, environment);
        if (then_block_type != else_block_type) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_expression.else_token, "if-expression branches must have the same type, found then: {s}, else: {s}", .{ try self.typeName(then_block_type), try self.typeName(else_block_type) });
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, then_block_type);
    }

    fn checkMatchExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        match_expression: *const ast.MatchExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const match_type = try self.checkMatchExpression(match_expression, environment);
        return self.recordNodeType(node_id, match_type);
    }

    fn checkArrayLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
        array_literal: *const ast.ArrayLiteral,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        if (array_literal.elements.len == 0) {
            if (environment.contextual_type_id) |type_id| {
                return self.recordNodeType(node_id, type_id);
            }

            try self.diagnostic_store.emitErrorFromToken(array_literal.left_bracket, "cannot infer the type of an empty array literal without a contextual type");
            return error.DiagnosticsEmitted;
        }

        const first_element_type = try self.checkExpression(&array_literal.elements[0], environment);

        for (array_literal.elements[1..]) |*element| {
            const element_type = try self.checkExpression(element, environment);
            if (element_type != first_element_type) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, element.primaryToken(), "array literal elements must all have the same type, expected {s}, found {s}", .{ try self.typeName(first_element_type), try self.typeName(element_type) });
                return error.DiagnosticsEmitted;
            }
        }

        const array_type_id = self.type_store.getOrCreateArrayType(first_element_type);
        return self.recordNodeType(node_id, array_type_id);
    }

    fn checkIndexAccessNode(
        self: *@This(),
        node_id: ast.NodeId,
        index_access: *const ast.IndexAccess,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const base_type_id = try self.checkExpression(index_access.base, environment);
        const element_type_id = switch (self.type_store.getType(base_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, index_access.left_bracket, "cannot index into non-array type {s}", .{try self.typeName(base_type_id)});
                return error.DiagnosticsEmitted;
            },
        };

        const index_type_id = try self.checkExpression(index_access.index, environment);
        if (index_type_id != self.type_store.integer_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, index_access.index.primaryToken(), "array index must be int, found {s}", .{try self.typeName(index_type_id)});
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, element_type_id);
    }

    fn checkExpressionStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        expression_statement: *const ast.ExpressionStatement,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const expression_type = try self.checkNode(
            expression_statement.expression,
            environment.withContextAndType(.Statement, null),
        );
        if (expression_type != self.type_store.unit_type_id) {
            try self.diagnostic_store.emitErrorFromToken(expression_statement.expression.primaryToken(), "expression statement must evaluate to unit");
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        environment: TypeCheckEnvironment,
    ) TypeError!void {
        const function_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const resolved_function = self.getResolvedFunction(function_symbol_id, environment.resolved_program);
        for (resolved_function.parameters) |parameter| {
            const parameter_type = self.resolveTypeReference(parameter.type_reference);
            self.type_by_symbol_id.put(parameter.symbol_id, parameter_type) catch unreachable;
        }

        try self.checkFunctionDefinitionReturnValue(
            function_node_id,
            function_definition,
            environment,
        );
    }

    fn checkFunctionDefinitionReturnValue(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        environment: TypeCheckEnvironment,
    ) TypeError!void {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const resolved_function = self.getResolvedFunction(symbol_id, environment.resolved_program);
        const function_return_type = self.resolveTypeReference(resolved_function.return_type_reference);

        const body_expression_type = try self.checkNode(
            function_definition.body_expression,
            environment.withContextAndType(.FunctionBody, function_return_type),
        );
        try self.checkReturnStatementsMatchType(
            function_definition.body_expression,
            function_return_type,
            environment.resolved_program,
        );

        const body_exit_behavior = environment.exit_behavior_by_node_id.get(
            function_definition.body_expression.id,
        ) orelse unreachable;
        switch (body_exit_behavior) {
            // This is okay, all control flow paths return and we validated that all return statements return the correct type
            .Terminates => {},
            .FallsThroughWithoutValue => {
                if (function_return_type != self.type_store.unit_type_id) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, function_definition.body_expression.primaryToken(), "function declared to return {s} has a path that falls through without returning a value", .{try self.typeName(function_return_type)});
                    return error.DiagnosticsEmitted;
                }
            },
            .FallsThroughWithValue => {
                if (function_return_type != body_expression_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, function_definition.body_expression.primaryToken(), "function declared to return {s} cannot fall through with a value of type {s}", .{ try self.typeName(function_return_type), try self.typeName(body_expression_type) });
                    return error.DiagnosticsEmitted;
                }
            },
        }
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
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, return_statement.return_token, "return statement expects value of type {s}, found {s}", .{ try self.typeName(function_return_type), try self.typeName(return_value_type) });
                        return error.DiagnosticsEmitted;
                    }
                } else {
                    if (function_return_type != self.type_store.unit_type_id) {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, return_statement.return_token, "return statement is missing a value for function return type {s}", .{try self.typeName(function_return_type)});
                        return error.DiagnosticsEmitted;
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
            .ForIn => |for_in| {
                try self.checkReturnStatementsMatchType(for_in.iterable, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(for_in.body_block, function_return_type, resolved_program);
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
            .MemberAccess => |member_access| {
                try self.checkReturnStatementsMatchType(member_access.base, function_return_type, resolved_program);
            },
            .StructureConstruction => |structure_construction| {
                for (structure_construction.fields) |field| {
                    try self.checkReturnStatementsMatchType(field.value, function_return_type, resolved_program);
                }
            },
            .AnonymousStructureLiteral => |anonymous_structure_literal| {
                for (anonymous_structure_literal.fields) |field| {
                    try self.checkReturnStatementsMatchType(field.value, function_return_type, resolved_program);
                }
            },
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    try self.checkReturnStatementsMatchType(element, function_return_type, resolved_program);
                }
            },
            .IndexAccess => |index_access| {
                try self.checkReturnStatementsMatchType(index_access.base, function_return_type, resolved_program);
                try self.checkReturnStatementsMatchType(index_access.index, function_return_type, resolved_program);
            },
            .ItemDefinition => {},
            .Identifier,
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .UnitLiteral,
            .Leave,
            .Continue,
            => {},
        }
    }

    pub fn resolveTypeReference(
        self: *@This(),
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
            .Array => |element_type_reference| self.type_store.getOrCreateArrayType(
                self.resolveTypeReference(element_type_reference.*),
            ),
        };
    }

    fn getResolvedFunction(
        self: *const @This(),
        function_symbol_id: symbols.SymbolId,
        resolved_program: *const symbols.ResolvedProgram,
    ) symbols.ResolvedFunction {
        _ = self;
        return resolved_program.resolved_function_by_symbol_id.get(function_symbol_id) orelse unreachable;
    }

    fn checkMatchExpression(
        self: *@This(),
        match_expression: *const ast.MatchExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const context = environment.context;
        const exhaustiveness_class: ExhaustivenessClass = if (match_expression.subject) |subject| class: {
            const subject_type = try self.checkNode(
                subject,
                environment.withContextAndType(.Expression, null),
            );
            break :class switch (self.getType(subject_type)) {
                .Boolean => .Boolean,
                .Integer => .IntegerOpen,
                .String => .StringOpen,
                else => {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, match_expression.match_token, "match subject must be boolean, integer, or string, found {s}", .{try self.typeName(subject_type)});
                    return error.DiagnosticsEmitted;
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
                        environment.withContextAndType(.Expression, null),
                    );
                    if (condition_type != self.type_store.boolean_type_id) {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, arm.pattern_or_condition.primaryToken(), "subjectless match arm condition must be boolean, found {s}", .{try self.typeName(condition_type)});
                        return error.DiagnosticsEmitted;
                    }
                },
                .Boolean => switch (arm.pattern_or_condition.kind) {
                    .BooleanLiteral => |token| {
                        if (token.kind.BooleanLiteral) {
                            if (saw_true) {
                                try self.diagnostic_store.emitErrorFromToken(token, "duplicate 'true' match arm");
                                return error.DiagnosticsEmitted;
                            }
                            saw_true = true;
                        } else {
                            if (saw_false) {
                                try self.diagnostic_store.emitErrorFromToken(token, "duplicate 'false' match arm");
                                return error.DiagnosticsEmitted;
                            }
                            saw_false = true;
                        }
                        self.type_by_node_id.put(arm.pattern_or_condition.id, self.type_store.boolean_type_id) catch unreachable;
                    },
                    else => {
                        try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "boolean match arms must use boolean literals");
                        return error.DiagnosticsEmitted;
                    },
                },
                .IntegerOpen => switch (arm.pattern_or_condition.kind) {
                    .IntegerLiteral => |token| {
                        _ = try self.checkNode(
                            arm.pattern_or_condition,
                            environment.withContextAndType(.Expression, null),
                        );
                        const value = token.kind.IntLiteral;
                        if (integer_patterns.contains(value)) {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, token, "duplicate integer match arm for value {d}", .{value});
                            return error.DiagnosticsEmitted;
                        }
                        integer_patterns.put(value, {}) catch unreachable;
                    },
                    else => {
                        const pattern_type = try self.checkNode(
                            arm.pattern_or_condition,
                            environment.withContextAndType(.Expression, null),
                        );
                        if (pattern_type != self.type_store.integer_type_id) {
                            try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "integer match arms must be integer expressions");
                            return error.DiagnosticsEmitted;
                        }
                    },
                },
                .StringOpen => {
                    const pattern_type = try self.checkNode(
                        arm.pattern_or_condition,
                        environment.withContextAndType(.Expression, null),
                    );
                    if (pattern_type != self.type_store.string_type_id) {
                        try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "string match arms must be string expressions");
                        return error.DiagnosticsEmitted;
                    }
                },
            }

            const body_type = try self.checkNode(
                arm.body,
                environment,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != body_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, arm.body.primaryToken(), "match arms must all produce the same type, expected {s}, found {s}", .{ try self.typeName(expected_type), try self.typeName(body_type) });
                    return error.DiagnosticsEmitted;
                }
            } else {
                arm_result_type = body_type;
            }
        }

        if (match_expression.else_arm) |else_arm| {
            const else_type = try self.checkNode(
                else_arm,
                environment,
            );
            if (arm_result_type) |expected_type| {
                if (expected_type != else_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, else_arm.primaryToken(), "match else arm must produce the same type as other arms, expected {s}, found {s}", .{ try self.typeName(expected_type), try self.typeName(else_type) });
                    return error.DiagnosticsEmitted;
                }
            } else {
                arm_result_type = else_type;
            }
        }

        const is_exhaustive = switch (exhaustiveness_class) {
            .Subjectless => match_expression.else_arm != null,
            .Boolean => (saw_true and saw_false) or match_expression.else_arm != null,
            .IntegerOpen => match_expression.else_arm != null,
            .StringOpen => match_expression.else_arm != null,
        };
        if (!is_exhaustive) {
            try self.diagnostic_store.emitErrorFromToken(match_expression.match_token, "match expression is not exhaustive");
            return error.DiagnosticsEmitted;
        }

        const result_type = arm_result_type orelse self.type_store.unit_type_id;
        if (context == .Statement and result_type != self.type_store.unit_type_id) {
            try self.diagnostic_store.emitErrorFromToken(match_expression.match_token, "match expression used as a statement must evaluate to unit");
            return error.DiagnosticsEmitted;
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

    fn recordMemberAccess(
        self: *@This(),
        node_id: ast.NodeId,
        member_access: typing.MemberAccess,
    ) void {
        self.member_access_by_node_id.put(node_id, member_access) catch unreachable;
    }

    fn getType(self: *const @This(), type_id: typing.TypeId) typing.Type {
        return self.type_store.getType(type_id);
    }
};
