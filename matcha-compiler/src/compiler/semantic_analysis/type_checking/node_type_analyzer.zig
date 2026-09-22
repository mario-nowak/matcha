const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");
const type_checking_types = @import("type_checking_types.zig");

pub const TypeError = type_checking_types.TypeError;
const ExhaustivenessClass = type_checking_types.ExhaustivenessClass;
const TypeCheckEnvironment = type_checking_types.TypeCheckEnvironment;
const PlaceInfo = type_checking_types.PlaceInfo;
const TypeCheckResult = type_checking_types.TypeCheckResult;
const ParentNodeExpectation = type_checking_types.ParentNodeExpectation;

/// Why a node is checked against an expected type. Selects the wording of the mismatch diagnostic.
pub const TypeCheckReason = union(enum) {
    BindingDeclaration: lexing.Token,
    AssignmentValue: lexing.Token,
    ReturnValue: lexing.Token,
    FunctionArgument,
    UnionCasePayload,
    StructureFieldValue: struct { field_name_token: lexing.Token, structure_name: []const u8 },
};

pub const NodeTypeAnalyzer = struct {
    allocator: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    type_store: typing.TypeStore,
    type_id_by_symbol_id: typing.TypeIdBySymbolId,
    type_id_by_node_id: typing.TypeIdByNodeId,
    member_access_by_node_id: typing.MemberAccessByNodeId,

    pub fn init(allocator: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{
            .allocator = allocator,
            .diagnostic_store = diagnostic_store,
            .type_store = typing.TypeStore.init(allocator),
            .type_id_by_symbol_id = typing.TypeIdBySymbolId.init(allocator),
            .type_id_by_node_id = typing.TypeIdByNodeId.init(allocator),
            .member_access_by_node_id = typing.MemberAccessByNodeId.init(allocator),
        };
    }

    fn resetState(self: *@This()) void {
        self.type_store = typing.TypeStore.init(self.allocator);
        self.type_id_by_symbol_id = typing.TypeIdBySymbolId.init(self.allocator);
        self.type_id_by_node_id = typing.TypeIdByNodeId.init(self.allocator);
        self.member_access_by_node_id = typing.MemberAccessByNodeId.init(self.allocator);
    }

    pub fn analyzeProgram(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    ) TypeError!TypeCheckResult {
        self.resetState();
        try self.seedModuleLevelItemTypes(resolved_program);

        const root_environment = TypeCheckEnvironment{
            .resolved_program = resolved_program,
            .exit_behavior_by_node_id = exit_behavior_by_node_id,
            .function_return_type_id = null,
        };
        for (resolved_program.program.statements) |*statement| {
            _ = try self.checkNode(statement, .forStatement, root_environment);
        }

        self.type_store.assertAllFinalized();

        return .{
            .type_store = self.type_store,
            .type_id_by_symbol_id = self.type_id_by_symbol_id,
            .type_id_by_node_id = self.type_id_by_node_id,
            .member_access_by_node_id = self.member_access_by_node_id,
        };
    }

    fn seedModuleLevelItemTypes(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        // First seed all user defined structures and unions as preliminary types to support forward references of these
        // types.
        var symbol_iterator = resolved_program.symbol_table.iterator();
        while (symbol_iterator.next()) |symbol| {
            const type_kind: typing.TypeKind = switch (symbol.kind) {
                .Structure => .Structure,
                .Union => .Union,
                else => continue,
            };
            const type_id = self.type_store.addPreliminaryType(type_kind);
            self.type_id_by_symbol_id.put(symbol.id, type_id) catch unreachable;
        }

        // Once we seeded all of those preliminary types, we can seeding all function types.
        symbol_iterator = resolved_program.symbol_table.iterator();
        while (symbol_iterator.next()) |symbol| {
            switch (symbol.kind) {
                .Function => self.seedFunctionTypes(symbol, resolved_program),
                else => {},
            }
        }

        // Finally we can finalize all the preliminary types.
        symbol_iterator = resolved_program.symbol_table.iterator();
        while (symbol_iterator.next()) |symbol| {
            // Skip if there is no type for this symbol.
            const type_id = self.type_id_by_symbol_id.get(symbol.id) orelse continue;

            const finalized_type: typing.Type = switch (symbol.kind) {
                .Structure => |structure_information| block: {
                    var fields = std.ArrayList(typing.StructureTypeField){};
                    for (structure_information.fields) |field| {
                        fields.append(self.allocator, .{
                            .name = field.name,
                            .type_id = self.resolveTypeReference(field.type_reference),
                        }) catch unreachable;
                    }

                    break :block .{
                        .Structure = .{
                            .symbol_id = symbol.id,
                            .name = symbol.name,
                            .fields = fields.toOwnedSlice(self.allocator) catch unreachable,
                            // TODO: refactor / remove that
                            .function_symbol_ids = structure_information.function_symbol_ids,
                        },
                    };
                },
                .Union => |union_information| block: {
                    var cases = std.ArrayList(typing.UnionTypeCase){};
                    for (union_information.cases) |case| {
                        cases.append(
                            self.allocator,
                            .{ .type_id = self.resolveTypeReference(case.type_reference) },
                        ) catch unreachable;
                    }
                    break :block .{
                        .Union = .{
                            .symbol_id = symbol.id,
                            .cases = cases.toOwnedSlice(self.allocator) catch unreachable,
                        },
                    };
                },
                else => continue,
            };

            self.type_store.finalizeType(type_id, finalized_type);
        }
    }

    fn seedFunctionTypes(
        self: *@This(),
        function_symbol: symbols.Symbol,
        resolved_program: *const symbols.ResolvedProgram,
    ) void {
        const function_information = switch (function_symbol.kind) {
            .Function => |function_information| function_information,
            else => unreachable,
        };

        var parameter_types = std.ArrayList(typing.TypeId){};
        for (function_information.parameter_symbol_ids) |parameter_symbol_id| {
            const parameter_type_reference = switch (resolved_program.symbol_table.getSymbol(parameter_symbol_id).kind) {
                .Binding => |binding_information| binding_information.declared_type_reference orelse unreachable,
                else => unreachable,
            };
            parameter_types.append(self.allocator, self.resolveTypeReference(parameter_type_reference)) catch unreachable;
        }

        const owned_parameter_types = parameter_types.toOwnedSlice(self.allocator) catch unreachable;
        const function_return_type = self.resolveTypeReference(function_information.return_type_reference);
        const function_type_id = self.type_store.addType(.{ .Function = .{
            .parameter_type_ids = owned_parameter_types,
            .return_type_id = function_return_type,
        } });
        self.type_id_by_symbol_id.put(function_symbol.id, function_type_id) catch unreachable;
        for (function_information.parameter_symbol_ids, owned_parameter_types) |parameter_symbol_id, parameter_type| {
            self.type_id_by_symbol_id.put(parameter_symbol_id, parameter_type) catch unreachable;
        }
    }

    fn getTypeName(self: *@This(), type_id: typing.TypeId) ![]const u8 {
        return self.type_store.getType(type_id).name(&self.type_store, self.allocator);
    }

    fn checkNode(
        self: *@This(),
        node: *const ast.Node,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const type_id = try self.dispatchCheckNode(node, parent_node_expectation, environment);

        // Functions are not first-class values yet. A function-typed node is only valid as the direct callee of a call.
        const is_callee = switch (parent_node_expectation.node_role) {
            .Expression => |kind| kind == .Callee,
            .Statement => false,
        };
        if (!is_callee and self.type_store.getType(type_id) == .Function) {
            try self.diagnostic_store.emitErrorFromToken(
                node.primaryToken(),
                "functions can only be called; function values are not supported yet",
            );
            return error.DiagnosticsEmitted;
        }

        return type_id;
    }

    fn dispatchCheckNode(
        self: *@This(),
        node: *const ast.Node,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        switch (node.kind) {
            .BindingDeclaration => |binding_declaration| return self.checkBindingDeclarationNode(node.id, &binding_declaration, environment),
            .ItemDefinition => |item_definition| return self.checkItemDefinitionNode(node.id, &item_definition, environment),
            .ReturnStatement => |return_statement| return self.checkReturnStatementNode(node.id, &return_statement, environment),
            .AssignmentStatement => |assignment_statement| return self.checkAssignmentStatementNode(node.id, &assignment_statement, environment),
            .Loop => |loop| return self.checkLoopNode(node.id, &loop, environment),
            .While => |while_statement| return self.checkWhileNode(node.id, &while_statement, environment),
            .ForIn => |for_in| return self.checkForInNode(node.id, &for_in, environment),
            .LeaveStatement => return self.checkLeaveStatementNode(node.id),
            .ContinueStatement => return self.checkContinueStatementNode(node.id),
            .CallExpression => |call_expression| return self.checkCallExpressionNode(node.id, &call_expression, parent_node_expectation, environment),
            .MemberExpression => |member_expression| return self.checkMemberExpressionNode(node.id, &member_expression, environment),
            .ImplicitMemberExpression => |implicit_member_expression| return self.checkImplicitMemberExpressionNode(node.id, &implicit_member_expression, parent_node_expectation, environment),
            .BinaryExpression => |binary_expression| return self.checkBinaryExpressionNode(node.id, &binary_expression, environment),
            .UnaryExpression => |unary_expression| return self.checkUnaryExpressionNode(node.id, &unary_expression, environment),
            .QualifiedStructureLiteral => |qualified_structure_literal| return self.checkQualifiedStructureLiteralNode(node.id, &qualified_structure_literal, environment),
            .StructureLiteral => |structure_literal| return self.checkStructureLiteralNode(node.id, &structure_literal, parent_node_expectation, environment),
            .Block => |block| return self.checkBlockNode(node.id, &block, parent_node_expectation, environment),
            .IntegerLiteral => return self.checkIntegerLiteralNode(node.id),
            .BooleanLiteral => return self.checkBooleanLiteralNode(node.id),
            .StringLiteral => return self.checkStringLiteralNode(node.id),
            .UnitLiteral => return self.checkUnitLiteralNode(node.id),
            .Identifier => |identifier_token| return self.checkIdentifierNode(node.id, identifier_token, environment),
            .IfStatement => |if_statement| return self.checkIfStatementNode(node.id, &if_statement, environment),
            .IfExpression => |if_expression| return self.checkIfExpressionNode(node.id, &if_expression, parent_node_expectation, environment),
            .MatchExpression => |match_expression| return self.checkMatchExpressionNode(node.id, &match_expression, parent_node_expectation, environment),
            .ExpressionStatement => |expression_statement| return self.checkExpressionStatementNode(node.id, &expression_statement, environment),
            .ArrayLiteral => |array_literal| return self.checkArrayLiteralNode(node.id, &array_literal, parent_node_expectation, environment),
            .IndexExpression => |index_expression| return self.checkIndexExpressionNode(node.id, &index_expression, environment),
        }
    }

    fn checkNodeAgainstExpectedType(
        self: *@This(),
        node: *const ast.Node,
        expected_type_id: typing.TypeId,
        reason: TypeCheckReason,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const node_type_id = try self.checkNode(node, .forExpressionWithType(expected_type_id), environment);

        if (node_type_id != expected_type_id) {
            const expected_type_name = try self.getTypeName(expected_type_id);
            const actual_type_name = try self.getTypeName(node_type_id);
            switch (reason) {
                .BindingDeclaration => |name_token| try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    name_token,
                    "declaration '{s}' expects {s}, found {s}",
                    .{ name_token.kind.Identifier, expected_type_name, actual_type_name },
                ),
                .AssignmentValue => |assignment_token| try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    assignment_token,
                    "cannot assign value of type {s} to target of type {s}",
                    .{ actual_type_name, expected_type_name },
                ),
                .ReturnValue => |return_token| try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    return_token,
                    "return statement expects value of type {s}, found {s}",
                    .{ expected_type_name, actual_type_name },
                ),
                .FunctionArgument => try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    node.primaryToken(),
                    "function argument expects {s}, found {s}",
                    .{ expected_type_name, actual_type_name },
                ),
                .UnionCasePayload => try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    node.primaryToken(),
                    "union initialization expects {s}, found {s}",
                    .{ expected_type_name, actual_type_name },
                ),
                .StructureFieldValue => |field| try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    field.field_name_token,
                    "field '{s}' on structure '{s}' expects {s}, found {s}",
                    .{ field.field_name_token.kind.Identifier, field.structure_name, expected_type_name, actual_type_name },
                ),
            }
            return error.DiagnosticsEmitted;
        }

        return node_type_id;
    }

    fn checkItemDefinitionNode(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: *const ast.ItemDefinition,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        switch (item_definition.definition) {
            .Function => |function_definition| try self.checkFunctionDefinitionNode(
                node_id,
                &function_definition,
                environment,
            ),
            .Structure => |structure_definition| {
                for (structure_definition.function_definitions) |*function_definition_node| {
                    const function_definition = function_definition_node.kind.ItemDefinition.definition.Function;
                    try self.checkFunctionDefinitionNode(
                        function_definition_node.id,
                        &function_definition,
                        environment,
                    );
                }
            },
            .Union => |union_definition| {
                for (union_definition.function_definitions) |*function_definition_node| {
                    const function_definition = function_definition_node.kind.ItemDefinition.definition.Function;
                    try self.checkFunctionDefinitionNode(
                        function_definition_node.id,
                        &function_definition,
                        environment,
                    );
                }
            },
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkQualifiedStructureLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
        qualified_structure_literal: *const ast.QualifiedStructureLiteral,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const structure_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const type_id = self.type_id_by_symbol_id.get(structure_symbol_id).?;
        return self.checkStructureLiteralFieldsAgainstType(
            node_id,
            qualified_structure_literal.fields,
            type_id,
            environment,
        );
    }

    fn checkStructureLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
        structure_literal: *const ast.StructureLiteral,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const type_id = parent_node_expectation.type_id orelse {
            try self.diagnostic_store.emitErrorFromToken(
                structure_literal.dot_token,
                "cannot infer the type of an anonymous structure literal without an expected type",
            );
            return error.DiagnosticsEmitted;
        };
        return self.checkStructureLiteralFieldsAgainstType(
            node_id,
            structure_literal.fields,
            type_id,
            environment,
        );
    }

    fn checkStructureLiteralFieldsAgainstType(
        self: *@This(),
        node_id: ast.NodeId,
        fields: []const ast.StructureFieldInitializer,
        type_id: typing.TypeId,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const structure_type = switch (self.type_store.getType(type_id)) {
            .Structure => |structure_type| structure_type,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, fields[0].name, "expected a structure type for this literal, found {s}", .{try self.getTypeName(type_id)});
                return error.DiagnosticsEmitted;
            },
        };

        var unique_field_names = std.StringHashMap(bool).init(self.allocator);
        defer unique_field_names.deinit();

        for (fields) |field| {
            const field_name = field.name.kind.Identifier;
            const existing_field_name = unique_field_names.get(field_name);
            if (existing_field_name) |_| {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, field.name, "duplicate field '{s}' in structure construction", .{field_name});
                return error.DiagnosticsEmitted;
            }
            unique_field_names.put(field_name, true) catch unreachable;

            const field_index = structure_type.getFieldIndex(field_name) orelse {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, field.name, "field '{s}' does not exist on structure '{s}'", .{ field_name, structure_type.name });
                return error.DiagnosticsEmitted;
            };
            const structure_type_field = structure_type.fields[@intCast(field_index)];
            _ = try self.checkNodeAgainstExpectedType(
                field.value,
                structure_type_field.type_id,
                .{ .StructureFieldValue = .{ .field_name_token = field.name, .structure_name = structure_type.name } },
                environment,
            );
        }

        for (structure_type.fields) |field| {
            const field_exists_in_construction = unique_field_names.get(field.name);
            if (field_exists_in_construction == null) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, fields[0].name, "missing field '{s}' in construction of '{s}'", .{ field.name, structure_type.name });
                return error.DiagnosticsEmitted;
            }
        }

        return self.recordNodeType(node_id, type_id);
    }

    fn checkBindingDeclarationNode(
        self: *@This(),
        node_id: ast.NodeId,
        binding_declaration: *const ast.BindingDeclaration,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const binding_information = environment.resolved_program.symbol_table.getSymbol(symbol_id).kind.Binding;
        const annotated_type_id_or_null = if (binding_information.declared_type_reference) |type_reference|
            self.resolveTypeReference(type_reference)
        else
            null;
        const value_type_id = if (annotated_type_id_or_null) |annotated_type_id|
            try self.checkNodeAgainstExpectedType(
                binding_declaration.value,
                annotated_type_id,
                .{ .BindingDeclaration = binding_declaration.name },
                environment,
            )
        else
            try self.checkNode(binding_declaration.value, .forExpression, environment);

        self.type_id_by_symbol_id.put(symbol_id, value_type_id) catch unreachable;
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkReturnStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        return_statement: *const ast.ReturnStatement,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const function_return_type_id = environment.function_return_type_id orelse {
            // Outside a function there is nothing to check the value against. Control flow validation reports the
            // misplaced return.
            if (return_statement.value) |return_value| {
                _ = try self.checkNode(return_value, .forExpression, environment);
            }
            return self.recordNodeType(node_id, self.type_store.unit_type_id);
        };

        if (return_statement.value) |return_value| {
            _ = try self.checkNodeAgainstExpectedType(
                return_value,
                function_return_type_id,
                .{ .ReturnValue = return_statement.return_token },
                environment,
            );
        } else if (function_return_type_id != self.type_store.unit_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(
                self.allocator,
                return_statement.return_token,
                "return statement is missing a value for function return type {s}",
                .{try self.getTypeName(function_return_type_id)},
            );
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkAssignmentStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        assignment_statement: *const ast.AssignmentStatement,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const place = try self.checkPlaceNode(assignment_statement.target, environment);

        switch (assignment_statement.operator) {
            .Assign => {
                _ = try self.checkNodeAgainstExpectedType(
                    assignment_statement.value,
                    place.type_id,
                    .{ .AssignmentValue = assignment_statement.assignment_token },
                    environment,
                );
            },
            .Compound => |binary_operator| {
                const value_type = try self.checkNode(assignment_statement.value, .forExpression, environment);
                const compound_result_type = try self.checkBinaryOperatorApplication(
                    assignment_statement.assignment_token,
                    binary_operator,
                    place.type_id,
                    value_type,
                );
                if (compound_result_type != place.type_id) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, assignment_statement.assignment_token, "compound assignment produces {s}, which cannot be assigned to target of type {s}", .{ try self.getTypeName(compound_result_type), try self.getTypeName(place.type_id) });
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

                const type_id = try self.checkNode(node, .forExpression, environment);
                return .{ .type_id = type_id };
            },
            .ImplicitMemberExpression => {
                try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to an implicit member expression");
                return error.DiagnosticsEmitted;
            },
            .MemberExpression => {
                const type_id = try self.checkNode(node, .forExpression, environment);
                const member_expression = self.member_access_by_node_id.get(node.id) orelse unreachable;
                return switch (member_expression) {
                    // TODO: not sure if this is correct honestly
                    .UnionTypeCaseAccess,
                    .StructureInstanceFieldAccess,
                    => .{ .type_id = type_id },
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
                    .UnionTypeFunctionAccess => {
                        try self.diagnostic_store.emitErrorFromToken(node.primaryToken(), "cannot assign to a union function");
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
            .IndexExpression => {
                const type_id = try self.checkNode(node, .forExpression, environment);
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
        _ = try self.checkNode(loop.body_block, .forStatement, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkWhileNode(
        self: *@This(),
        node_id: ast.NodeId,
        while_statement: *const ast.While,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const while_condition_type = try self.checkNode(while_statement.condition, .forExpression, environment);
        if (while_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, while_statement.while_token, "while condition must be boolean, found {s}", .{try self.getTypeName(while_condition_type)});
            return error.DiagnosticsEmitted;
        }

        if (while_statement.update) |update| {
            _ = try self.checkNode(update, .forStatement, environment);
        }

        _ = try self.checkNode(while_statement.body_block, .forStatement, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkForInNode(
        self: *@This(),
        node_id: ast.NodeId,
        for_in: *const ast.ForIn,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const iterable_type_id = try self.checkNode(for_in.iterable, .forExpression, environment);
        const item_type_id = switch (self.type_store.getType(iterable_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, for_in.in_token, "for-in iterable must be an array, found {s}", .{try self.getTypeName(iterable_type_id)});
                return error.DiagnosticsEmitted;
            },
        };

        const item_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        self.type_id_by_symbol_id.put(item_symbol_id, item_type_id) catch unreachable;

        _ = try self.checkNode(for_in.body_block, .forStatement, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkLeaveStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkContinueStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
    ) TypeError!typing.TypeId {
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkCallExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        call_expression: *const ast.CallExpression,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        // The callee receives the type expected of the whole call so that an implicit member expression like `.Some`
        // can resolve against it. Callees that infer their own type ignore it.
        const callee_type_id = try self.checkNode(
            call_expression.callee,
            .forCallee(parent_node_expectation.type_id),
            environment,
        );

        switch (self.type_store.getType(callee_type_id)) {
            .Function => |function_type| {
                if (call_expression.arguments.len != function_type.parameter_type_ids.len) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, call_expression.left_parenthesis, "function expects {d} arguments, found {d}", .{ function_type.parameter_type_ids.len, call_expression.arguments.len });
                    return error.DiagnosticsEmitted;
                }

                for (call_expression.arguments, function_type.parameter_type_ids) |*argument, parameter_type_id| {
                    _ = try self.checkNodeAgainstExpectedType(argument, parameter_type_id, .FunctionArgument, environment);
                }

                return self.recordNodeType(node_id, function_type.return_type_id);
            },
            .Union => |union_type| {
                if (call_expression.arguments.len != 1) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(
                        self.allocator,
                        call_expression.left_parenthesis,
                        "union initialization expects 1 arguments, found {d}",
                        .{call_expression.arguments.len},
                    );
                    return error.DiagnosticsEmitted;
                }
                const argument = call_expression.arguments[0];

                const member_access = self.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable;
                const union_type_case_index = switch (member_access) {
                    .UnionTypeCaseAccess => |union_type_case_access| union_type_case_access.case_index,
                    else => unreachable,
                };
                const union_type_case = union_type.cases[union_type_case_index];
                _ = try self.checkNodeAgainstExpectedType(&argument, union_type_case.type_id, .UnionCasePayload, environment);

                return self.recordNodeType(node_id, callee_type_id);
            },
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, call_expression.left_parenthesis, "cannot call value of non-function type {s}", .{try self.getTypeName(callee_type_id)});
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn checkMemberExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        member_expression: *const ast.MemberExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const member_name = member_expression.member_name_token.kind.Identifier;
        if (member_expression.base.kind == .Identifier) {
            const base_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(member_expression.base.id) orelse unreachable;
            const base_symbol = environment.resolved_program.symbol_table.getSymbol(base_symbol_id);
            switch (base_symbol.kind) {
                .Structure => {
                    const base_type_id = self.type_id_by_symbol_id.get(base_symbol_id) orelse unreachable;
                    const structure_type = switch (self.type_store.getType(base_type_id)) {
                        .Structure => |structure_type| structure_type,
                        else => unreachable,
                    };
                    const function_symbol_id = structure_type.getFunctionSymbolId(&environment.resolved_program.symbol_table, member_name) orelse {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "no function named '{s}' exists on structure type '{s}'", .{ member_name, structure_type.name });
                        return error.DiagnosticsEmitted;
                    };

                    self.recordMemberAccess(node_id, .{ .StructureTypeFunctionAccess = .{
                        .structure_symbol_id = base_symbol_id,
                        .function_symbol_id = function_symbol_id,
                    } });
                    const function_type_id = self.type_id_by_symbol_id.get(function_symbol_id) orelse unreachable;
                    return self.recordNodeType(node_id, function_type_id);
                },
                .Union => |union_symbol_information| {
                    const base_type_id = self.type_id_by_symbol_id.get(base_symbol_id) orelse unreachable;
                    for (union_symbol_information.cases, 0..) |union_case, case_index| {
                        if (std.mem.eql(u8, union_case.name, member_name)) {
                            // TODO: add comment
                            self.recordMemberAccess(node_id, .{ .UnionTypeCaseAccess = .{ .case_index = case_index } });

                            // If the member name matches any case of the union type, the member expression has the type
                            // of that union.
                            return self.recordNodeType(node_id, base_type_id);
                        }
                    }
                    for (union_symbol_information.function_symbol_ids) |function_symbol_id| {
                        const function_symbol = environment.resolved_program.symbol_table.getSymbol(function_symbol_id);
                        if (std.mem.eql(u8, function_symbol.name, member_name)) {
                            const function_type_id = self.type_id_by_symbol_id.get(function_symbol_id) orelse unreachable;
                            self.recordMemberAccess(node_id, .UnionTypeFunctionAccess);

                            return self.recordNodeType(node_id, function_type_id);
                        }
                    }

                    try self.diagnostic_store.emitFormattedErrorFromToken(
                        self.allocator,
                        member_expression.member_name_token,
                        "no function or case named '{s}' exists on union type '{s}'",
                        .{ member_name, base_symbol.name },
                    );
                    return error.DiagnosticsEmitted;
                },
                .Binding => return self.checkInstanceMemberExpressionNode(
                    node_id,
                    member_expression,
                    environment,
                ),
                .Function => {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "cannot access member '{s}' on a function", .{member_name});
                    return error.DiagnosticsEmitted;
                },
            }
        }

        return self.checkInstanceMemberExpressionNode(
            node_id,
            member_expression,
            environment,
        );
    }

    fn checkImplicitMemberExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        implicit_member_expression: *const ast.ImplicitMemberExpression,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const expected_type_id = parent_node_expectation.type_id orelse {
            try self.diagnostic_store.emitErrorFromToken(
                implicit_member_expression.member_name_token,
                "cannot infer the type of an implicit member expression without an expected type",
            );
            return error.DiagnosticsEmitted;
        };

        const expected_type = self.type_store.getType(expected_type_id);
        if (expected_type != .Union) {
            try self.diagnostic_store.emitFormattedErrorFromToken(
                self.allocator,
                implicit_member_expression.member_name_token,
                "implicit member expressions can only be used when the expected type is a union, found '{s}'",
                .{try self.getTypeName(expected_type_id)},
            );
            return error.DiagnosticsEmitted;
        }

        const union_symbol = environment.resolved_program.symbol_table.getSymbol(expected_type.Union.symbol_id);
        const member_name = implicit_member_expression.member_name_token.kind.Identifier;
        for (union_symbol.kind.Union.cases, 0..) |union_case, case_index| {
            if (std.mem.eql(u8, union_case.name, member_name)) {
                self.recordMemberAccess(node_id, .{ .UnionTypeCaseAccess = .{ .case_index = case_index } });

                return self.recordNodeType(node_id, expected_type_id);
            }
        }

        try self.diagnostic_store.emitFormattedErrorFromToken(
            self.allocator,
            implicit_member_expression.member_name_token,
            "no case named '{s}' exists on union type '{s}'",
            .{ member_name, union_symbol.name },
        );
        return error.DiagnosticsEmitted;
    }

    fn checkInstanceMemberExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        member_expression: *const ast.MemberExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const member_name = member_expression.member_name_token.kind.Identifier;
        const base_type_id = try self.checkNode(member_expression.base, .forExpression, environment);
        switch (self.type_store.getType(base_type_id)) {
            .Structure => |structure_type| {
                const field_index = structure_type.getFieldIndex(member_name);
                if (field_index) |structure_field_index| {
                    self.recordMemberAccess(node_id, .{ .StructureInstanceFieldAccess = .{ .field_index = structure_field_index } });
                    return self.recordNodeType(node_id, structure_type.fields[@intCast(structure_field_index)].type_id);
                }

                const function_symbol_id = structure_type.getFunctionSymbolId(&environment.resolved_program.symbol_table, member_name);
                if (function_symbol_id) |structure_function_symbol_id| {
                    // Instance method access binds the receiver and drops the `self` parameter from the callable type.
                    const bound_function_type_id = try self.bindInstanceMethodFunctionType(
                        member_expression.member_name_token,
                        structure_function_symbol_id,
                        base_type_id,
                    );
                    self.recordMemberAccess(node_id, .{ .StructureInstanceMethodAccess = .{
                        .structure_symbol_id = structure_type.symbol_id,
                        .function_symbol_id = structure_function_symbol_id,
                    } });
                    return self.recordNodeType(node_id, bound_function_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "type '{s}' has no member named '{s}'", .{ structure_type.name, member_name });
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

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "array has no member named '{s}'", .{member_name});
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

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "string has no member named '{s}'", .{member_name});
                return error.DiagnosticsEmitted;
            },
            .Integer => {
                if (std.mem.eql(u8, member_name, "toString")) {
                    const to_string_function_type_id = self.getStringMethodFunctionTypeId(&.{}, self.type_store.string_type_id);
                    self.recordMemberAccess(node_id, .{ .IntegerInstanceMethodAccess = .ToString });
                    return self.recordNodeType(node_id, to_string_function_type_id);
                }

                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "int has no member named '{s}'", .{member_name});
                return error.DiagnosticsEmitted;
            },
            // TODO: todo: this is missing unions
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_expression.member_name_token, "cannot access member '{s}' on type {s}", .{ member_name, try self.getTypeName(base_type_id) });
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
        return self.type_store.addType(.{ .Function = .{
            .parameter_type_ids = parameter_types,
            .return_type_id = self.type_store.unit_type_id,
        } });
    }

    fn getStringMethodFunctionTypeId(
        self: *@This(),
        parameter_type_ids: []const typing.TypeId,
        return_type_id: typing.TypeId,
    ) typing.TypeId {
        const parameter_types = self.allocator.alloc(typing.TypeId, parameter_type_ids.len) catch unreachable;
        @memcpy(parameter_types, parameter_type_ids);

        return self.type_store.addType(.{ .Function = .{
            .parameter_type_ids = parameter_types,
            .return_type_id = return_type_id,
        } });
    }

    fn bindInstanceMethodFunctionType(
        self: *@This(),
        member_name_token: lexing.Token,
        function_symbol_id: symbols.SymbolId,
        receiver_type_id: typing.TypeId,
    ) TypeError!typing.TypeId {
        const function_type_id = self.type_id_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_type = switch (self.type_store.getType(function_type_id)) {
            .Function => |function_type| function_type,
            else => unreachable,
        };

        if (function_type.parameter_type_ids.len == 0) {
            try self.diagnostic_store.emitErrorFromToken(member_name_token, "structure instance method is missing a receiver parameter");
            return error.DiagnosticsEmitted;
        }

        if (function_type.parameter_type_ids[0] != receiver_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, member_name_token, "structure instance method receiver expects {s}, found {s}", .{ try self.getTypeName(function_type.parameter_type_ids[0]), try self.getTypeName(receiver_type_id) });
            return error.DiagnosticsEmitted;
        }

        var remaining_parameter_types = std.ArrayList(typing.TypeId){};
        defer remaining_parameter_types.deinit(self.allocator);
        for (function_type.parameter_type_ids[1..]) |parameter_type_id| {
            remaining_parameter_types.append(self.allocator, parameter_type_id) catch unreachable;
        }

        return self.type_store.addType(.{ .Function = .{
            .parameter_type_ids = remaining_parameter_types.toOwnedSlice(self.allocator) catch unreachable,
            .return_type_id = function_type.return_type_id,
        } });
    }

    fn checkBinaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        binary_expression: *const ast.BinaryExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const left_expression_type = try self.checkNode(binary_expression.left, .forExpression, environment);
        const right_expression_type = try self.checkNode(binary_expression.right, .forExpression, environment);
        const result_type_id = try self.checkBinaryOperatorApplication(
            binary_expression.operator_token,
            binary_expression.operator,
            left_expression_type,
            right_expression_type,
        );
        return self.recordNodeType(node_id, result_type_id);
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
                        .{ binary_operator.name(), try self.getTypeName(operator_rule.argument_type_id), try self.getTypeName(right_operand_type) },
                    );
                    return error.DiagnosticsEmitted;
                }
                return operator_rule.return_type_id;
            } else {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, operator_token, "binary operator '{s}' is not supported for left operand type {s}", .{ binary_operator.name(), try self.getTypeName(left_operand_type) });
                return error.DiagnosticsEmitted;
            }
        } else {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, operator_token, "no binary operator rules exist for left operand type {s}", .{try self.getTypeName(left_operand_type)});
            return error.DiagnosticsEmitted;
        }
    }

    fn checkUnaryExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        unary_expression: *const ast.UnaryExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const operand_type = try self.checkNode(unary_expression.operand, .forExpression, environment);
        if (typing.getUnaryOperatorRules(&self.type_store, operand_type)) |rules_for_operand_type| {
            if (rules_for_operand_type.get(unary_expression.operator)) |operator_rule| {
                return self.recordNodeType(node_id, operator_rule.return_type_id);
            } else {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, unary_expression.operator_token, "unary operator '{s}' is not supported for operand type {s}", .{ unary_expression.operator.name(), try self.getTypeName(operand_type) });
                return error.DiagnosticsEmitted;
            }
        } else {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, unary_expression.operator_token, "no unary operator rules exist for operand type {s}", .{try self.getTypeName(operand_type)});
            return error.DiagnosticsEmitted;
        }
    }

    fn checkBlockNode(
        self: *@This(),
        node_id: ast.NodeId,
        block: *const ast.Block,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        if (parent_node_expectation.node_role == .Statement and block.result != null) {
            try self.diagnostic_store.emitErrorFromToken(block.left_brace, "block cannot have a trailing expression in statement context");
            return error.DiagnosticsEmitted;
        }

        for (block.statements) |*statement| {
            _ = try self.checkNode(statement, .forStatement, environment);
        }
        if (block.result) |result_node| {
            const result_type = try self.checkNode(result_node, parent_node_expectation.forwarded(), environment);
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
        identifier_token: lexing.Token,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(node_id).?;
        const symbol = environment.resolved_program.symbol_table.getSymbol(symbol_id);
        switch (symbol.kind) {
            .Binding, .Function => {},
            // A type name is only valid as the base of a member expression or in a qualified structure literal. Both are
            // handled by their own nodes without checking the name as an expression, so any type name that reaches this
            // point is used as a value.
            .Structure, .Union => {
                try self.diagnostic_store.emitFormattedErrorFromToken(
                    self.allocator,
                    identifier_token,
                    "'{s}' is a type and cannot be used as a value",
                    .{symbol.name},
                );
                return error.DiagnosticsEmitted;
            },
        }
        const symbol_type = self.type_id_by_symbol_id.get(symbol_id).?;
        return self.recordNodeType(node_id, symbol_type);
    }

    fn checkIfStatementNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_statement: *const ast.IfStatement,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkNode(if_statement.condition, .forExpression, environment);
        if (if_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_statement.if_token, "if condition must be boolean, found {s}", .{try self.getTypeName(if_condition_type)});
            return error.DiagnosticsEmitted;
        }

        _ = try self.checkNode(if_statement.then_branch, .forStatement, environment);
        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkIfExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        if_expression: *const ast.IfExpression,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const if_condition_type = try self.checkNode(if_expression.condition, .forExpression, environment);
        if (if_condition_type != self.type_store.boolean_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_expression.if_token, "if condition must be boolean, found {s}", .{try self.getTypeName(if_condition_type)});
            return error.DiagnosticsEmitted;
        }

        const then_block_type = try self.checkNode(if_expression.then_block, parent_node_expectation.forwarded(), environment);
        const else_block_type = try self.checkNode(if_expression.else_block, parent_node_expectation.forwarded(), environment);
        if (then_block_type != else_block_type) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, if_expression.else_token, "if-expression branches must have the same type, found then: {s}, else: {s}", .{ try self.getTypeName(then_block_type), try self.getTypeName(else_block_type) });
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, then_block_type);
    }

    fn checkMatchExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        match_expression: *const ast.MatchExpression,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const match_type = try self.checkMatchExpression(match_expression, parent_node_expectation, environment);
        return self.recordNodeType(node_id, match_type);
    }

    fn checkArrayLiteralNode(
        self: *@This(),
        node_id: ast.NodeId,
        array_literal: *const ast.ArrayLiteral,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        if (array_literal.elements.len == 0) {
            if (parent_node_expectation.type_id) |type_id| {
                return self.recordNodeType(node_id, type_id);
            }

            try self.diagnostic_store.emitErrorFromToken(array_literal.left_bracket, "cannot infer the type of an empty array literal without an expected type");
            return error.DiagnosticsEmitted;
        }

        const first_element_type = try self.checkNode(&array_literal.elements[0], .forExpression, environment);

        for (array_literal.elements[1..]) |*element| {
            const element_type = try self.checkNode(element, .forExpression, environment);
            if (element_type != first_element_type) {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, element.primaryToken(), "array literal elements must all have the same type, expected {s}, found {s}", .{ try self.getTypeName(first_element_type), try self.getTypeName(element_type) });
                return error.DiagnosticsEmitted;
            }
        }

        const array_type_id = self.type_store.getOrCreateArrayType(first_element_type);
        return self.recordNodeType(node_id, array_type_id);
    }

    fn checkIndexExpressionNode(
        self: *@This(),
        node_id: ast.NodeId,
        index_expression: *const ast.IndexExpression,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const base_type_id = try self.checkNode(index_expression.base, .forExpression, environment);
        const element_type_id = switch (self.type_store.getType(base_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, index_expression.left_bracket, "cannot index into non-array type {s}", .{try self.getTypeName(base_type_id)});
                return error.DiagnosticsEmitted;
            },
        };

        const index_type_id = try self.checkNode(index_expression.index, .forExpression, environment);
        if (index_type_id != self.type_store.integer_type_id) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, index_expression.index.primaryToken(), "array index must be int, found {s}", .{try self.getTypeName(index_type_id)});
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
        const expression_type = try self.checkNode(expression_statement.expression, .forStatement, environment);
        if (expression_type != self.type_store.unit_type_id) {
            try self.diagnostic_store.emitErrorFromToken(expression_statement.expression.primaryToken(), "expression statement must evaluate to unit");
            return error.DiagnosticsEmitted;
        }

        return self.recordNodeType(node_id, self.type_store.unit_type_id);
    }

    fn checkFunctionDefinitionNode(
        self: *@This(),
        function_definition_node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        environment: TypeCheckEnvironment,
    ) TypeError!void {
        const function_symbol_id = environment.resolved_program.symbol_id_by_node_id.get(function_definition_node_id).?;
        const function_information = self.getFunctionSymbolInformation(function_symbol_id, environment.resolved_program);
        for (function_information.parameter_symbol_ids) |parameter_symbol_id| {
            const declared_type_reference = switch (environment.resolved_program.symbol_table.getSymbol(parameter_symbol_id).kind) {
                .Binding => |binding_information| binding_information.declared_type_reference orelse unreachable,
                else => unreachable,
            };
            const parameter_type = self.resolveTypeReference(declared_type_reference);
            self.type_id_by_symbol_id.put(parameter_symbol_id, parameter_type) catch unreachable;
        }

        try self.checkFunctionDefinitionReturnValue(
            function_definition_node_id,
            function_definition,
            environment,
        );
    }

    fn checkFunctionDefinitionReturnValue(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        environment: TypeCheckEnvironment,
    ) TypeError!void {
        const symbol_id = environment.resolved_program.symbol_id_by_node_id.get(function_node_id).?;
        const function_information = self.getFunctionSymbolInformation(symbol_id, environment.resolved_program);
        const function_return_type = self.resolveTypeReference(function_information.return_type_reference);

        const body_expression_type = try self.checkNode(
            function_definition.body_expression,
            .forExpressionWithType(function_return_type),
            environment.copyWithFunctionReturnType(function_return_type),
        );

        const body_exit_behavior = environment.exit_behavior_by_node_id.get(
            function_definition.body_expression.id,
        ) orelse unreachable;
        switch (body_exit_behavior) {
            // This is okay, all control flow paths return and we validated that all return statements return the correct type
            .Terminates => {},
            .FallsThroughWithoutValue => {
                if (function_return_type != self.type_store.unit_type_id) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, function_definition.body_expression.primaryToken(), "function declared to return {s} has a path that falls through without returning a value", .{try self.getTypeName(function_return_type)});
                    return error.DiagnosticsEmitted;
                }
            },
            .FallsThroughWithValue => {
                if (function_return_type != body_expression_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, function_definition.body_expression.primaryToken(), "function declared to return {s} cannot fall through with a value of type {s}", .{ try self.getTypeName(function_return_type), try self.getTypeName(body_expression_type) });
                    return error.DiagnosticsEmitted;
                }
            },
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
            .Symbol => |symbol_id| self.type_id_by_symbol_id.get(symbol_id) orelse unreachable,
            .Array => |element_type_reference| self.type_store.getOrCreateArrayType(
                self.resolveTypeReference(element_type_reference.*),
            ),
        };
    }

    fn getFunctionSymbolInformation(
        self: *const @This(),
        function_symbol_id: symbols.SymbolId,
        resolved_program: *const symbols.ResolvedProgram,
    ) symbols.FunctionSymbolInformation {
        _ = self;
        return switch (resolved_program.symbol_table.getSymbol(function_symbol_id).kind) {
            .Function => |function_information| function_information,
            else => unreachable,
        };
    }

    fn checkMatchExpression(
        self: *@This(),
        match_expression: *const ast.MatchExpression,
        parent_node_expectation: ParentNodeExpectation,
        environment: TypeCheckEnvironment,
    ) TypeError!typing.TypeId {
        const context = parent_node_expectation.node_role;
        const exhaustiveness_class: ExhaustivenessClass = if (match_expression.subject) |subject| class: {
            const subject_type = try self.checkNode(subject, .forExpression, environment);
            break :class switch (self.getType(subject_type)) {
                .Boolean => .Boolean,
                .Integer => .IntegerOpen,
                .String => .StringOpen,
                else => {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, match_expression.match_token, "match subject must be boolean, integer, or string, found {s}", .{try self.getTypeName(subject_type)});
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
                    const condition_type = try self.checkNode(arm.pattern_or_condition, .forExpression, environment);
                    if (condition_type != self.type_store.boolean_type_id) {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, arm.pattern_or_condition.primaryToken(), "subjectless match arm condition must be boolean, found {s}", .{try self.getTypeName(condition_type)});
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
                        self.type_id_by_node_id.put(arm.pattern_or_condition.id, self.type_store.boolean_type_id) catch unreachable;
                    },
                    else => {
                        try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "boolean match arms must use boolean literals");
                        return error.DiagnosticsEmitted;
                    },
                },
                .IntegerOpen => switch (arm.pattern_or_condition.kind) {
                    .IntegerLiteral => |token| {
                        _ = try self.checkNode(arm.pattern_or_condition, .forExpression, environment);
                        const value = token.kind.IntLiteral;
                        if (integer_patterns.contains(value)) {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, token, "duplicate integer match arm for value {d}", .{value});
                            return error.DiagnosticsEmitted;
                        }
                        integer_patterns.put(value, {}) catch unreachable;
                    },
                    else => {
                        const pattern_type = try self.checkNode(arm.pattern_or_condition, .forExpression, environment);
                        if (pattern_type != self.type_store.integer_type_id) {
                            try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "integer match arms must be integer expressions");
                            return error.DiagnosticsEmitted;
                        }
                    },
                },
                .StringOpen => {
                    const pattern_type = try self.checkNode(arm.pattern_or_condition, .forExpression, environment);
                    if (pattern_type != self.type_store.string_type_id) {
                        try self.diagnostic_store.emitErrorFromToken(arm.pattern_or_condition.primaryToken(), "string match arms must be string expressions");
                        return error.DiagnosticsEmitted;
                    }
                },
            }

            const body_type = try self.checkNode(arm.body, parent_node_expectation.forwarded(), environment);
            if (arm_result_type) |expected_type| {
                if (expected_type != body_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, arm.body.primaryToken(), "match arms must all produce the same type, expected {s}, found {s}", .{ try self.getTypeName(expected_type), try self.getTypeName(body_type) });
                    return error.DiagnosticsEmitted;
                }
            } else {
                arm_result_type = body_type;
            }
        }

        if (match_expression.else_arm) |else_arm| {
            const else_type = try self.checkNode(else_arm, parent_node_expectation.forwarded(), environment);
            if (arm_result_type) |expected_type| {
                if (expected_type != else_type) {
                    try self.diagnostic_store.emitFormattedErrorFromToken(self.allocator, else_arm.primaryToken(), "match else arm must produce the same type as other arms, expected {s}, found {s}", .{ try self.getTypeName(expected_type), try self.getTypeName(else_type) });
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
        self.type_id_by_node_id.put(node_id, node_type) catch unreachable;
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
