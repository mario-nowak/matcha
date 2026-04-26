const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const scope = @import("scope.zig");

pub const NameResolutionError = error{
    UndefinedIdentifier,
    InvalidTypeAnnotation,
    ValueAlreadyDeclared,
    CannotAssignToImmutable,
    FunctionAlreadyDefined,
    StructureAlreadyDefined,
};

const ModuleShadowing = enum {
    Forbidden,
    Allowed,
};

const ResolutionContext = struct {
    module_shadowing: ModuleShadowing,
};

pub const NameResolver = struct {
    allocator: std.mem.Allocator,
    symbol_table: symbols.SymbolTable,
    symbol_id_by_node_id: symbols.SymbolIdByNodeId,
    resolved_item_by_symbol_id: symbols.ResolvedItemBySymbolId,
    type_reference_by_type_annotation_id: symbols.TypeReferenceByTypeAnnotationId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_table = symbols.SymbolTable.init(allocator),
            .symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(allocator),
            .resolved_item_by_symbol_id = symbols.ResolvedItemBySymbolId.init(allocator),
            .type_reference_by_type_annotation_id = symbols.TypeReferenceByTypeAnnotationId.init(allocator),
        };
    }

    pub fn resolveProgram(self: *@This(), program: *const ast.Program) !symbols.ResolvedProgram {
        const resolved_program = try self.resolveModule(program);

        return resolved_program;
    }

    fn resolveModule(self: *@This(), program: *const ast.Program) !symbols.ResolvedProgram {
        var root_scope = scope.Scope.init(self.allocator, null);
        self.symbol_table = symbols.SymbolTable.init(self.allocator);
        self.symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(self.allocator);
        self.resolved_item_by_symbol_id = symbols.ResolvedItemBySymbolId.init(self.allocator);
        self.type_reference_by_type_annotation_id = symbols.TypeReferenceByTypeAnnotationId.init(self.allocator);

        var module_scope = try self.buildModuleScope(program);

        self.addPrintIntBuiltinDebuggingFunction(&module_scope);
        self.addPrintStringBuiltinDebuggingFunction(&module_scope);

        for (program.statements) |statement| {
            try self.resolveNode(&statement, &root_scope, &module_scope, .{
                .module_shadowing = .Forbidden,
            });
        }

        return .{
            .program = program.*,
            .symbol_id_by_node_id = self.symbol_id_by_node_id,
            .symbol_table = self.symbol_table,
            .resolved_item_by_symbol_id = self.resolved_item_by_symbol_id,
            .type_reference_by_type_annotation_id = self.type_reference_by_type_annotation_id,
        };
    }

    fn addPrintIntBuiltinDebuggingFunction(self: *@This(), module_scope: *scope.ModuleScope) void {
        const print_int_symbol = self.symbol_table.insertSymbol(.{
            .name = "printInt",
            .declared_at = null,
            .kind = .{ .Function = .{ .implementation = .BuiltinPrintInt } },
        });
        module_scope.insertSymbol(print_int_symbol.name, print_int_symbol.id);
        const parameter_symbol = self.symbol_table.insertSymbol(.{
            .name = "value",
            .declared_at = null,
            .kind = .{ .Binding = .{ .binding_mutability = symbols.BindingMutability.Immutable } },
        });
        self.appendResolvedItem(.{
            .Function = .{
                .symbol_id = print_int_symbol.id,
                .name = print_int_symbol.name,
                .parameters = self.allocator.dupe(symbols.ResolvedParameter, &.{.{
                    .symbol_id = parameter_symbol.id,
                    .name = parameter_symbol.name,
                    .type_reference = .{ .Builtin = .Integer },
                }}) catch unreachable,
                .return_type_reference = .{ .Builtin = .Unit },
                .implementation = .builtin,
            },
        });
    }

    fn addPrintStringBuiltinDebuggingFunction(self: *@This(), module_scope: *scope.ModuleScope) void {
        const print_string_symbol = self.symbol_table.insertSymbol(.{
            .name = "printString",
            .declared_at = null,
            .kind = .{ .Function = .{ .implementation = .BuiltinPrintString } },
        });
        module_scope.insertSymbol(print_string_symbol.name, print_string_symbol.id);
        const parameter_symbol = self.symbol_table.insertSymbol(.{
            .name = "value",
            .declared_at = null,
            .kind = .{ .Binding = .{ .binding_mutability = symbols.BindingMutability.Immutable } },
        });
        self.appendResolvedItem(.{
            .Function = .{
                .symbol_id = print_string_symbol.id,
                .name = print_string_symbol.name,
                .parameters = self.allocator.dupe(symbols.ResolvedParameter, &.{.{
                    .symbol_id = parameter_symbol.id,
                    .name = parameter_symbol.name,
                    .type_reference = .{ .Builtin = .String },
                }}) catch unreachable,
                .return_type_reference = .{ .Builtin = .Unit },
                .implementation = .builtin,
            },
        });
    }

    fn buildModuleScope(self: *@This(), program: *const ast.Program) NameResolutionError!scope.ModuleScope {
        var module_scope = scope.ModuleScope.init(self.allocator, null);

        for (program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |_| {
                        const function_name = item_definition.identifier_token.kind.Identifier;
                        module_scope.validateNotInScope(function_name) catch {
                            std.debug.print("Semantic Error: Function already defined in module scope: {s}\n", .{function_name});
                            return NameResolutionError.FunctionAlreadyDefined;
                        };

                        const function_symbol = self.symbol_table.insertSymbol(.{
                            .name = function_name,
                            .declared_at = item_definition.item_token,
                            .kind = .{ .Function = .{ .implementation = .UserDefined } },
                        });
                        self.symbol_id_by_node_id.put(statement.id, function_symbol.id) catch unreachable;
                        module_scope.insertSymbol(
                            function_name,
                            function_symbol.id,
                        );
                    },
                    .Structure => |_| {
                        const structure_name = item_definition.identifier_token.kind.Identifier;
                        module_scope.validateNotInScope(structure_name) catch {
                            std.debug.print("Semantic Error: Structure already defined in module scope: {s}\n", .{structure_name});
                            return NameResolutionError.StructureAlreadyDefined;
                        };

                        const structure_symbol = self.symbol_table.insertSymbol(.{
                            .name = structure_name,
                            .declared_at = item_definition.item_token,
                            .kind = .{ .Structure = {} },
                        });
                        self.symbol_id_by_node_id.put(statement.id, structure_symbol.id) catch unreachable;
                        module_scope.insertSymbol(
                            structure_name,
                            structure_symbol.id,
                        );
                    },
                },
                else => {},
            }
        }

        return module_scope;
    }

    fn resolveNode(
        self: *@This(),
        node: *const ast.Node,
        node_scope: *scope.Scope,
        module_scope: *scope.ModuleScope,
        context: ResolutionContext,
    ) NameResolutionError!void {
        switch (node.kind) {
            .Declaration => |declaration| {
                const declaration_name = declaration.name.kind.Identifier;

                if (context.module_shadowing == .Forbidden) {
                    if (module_scope.lookupSymbol(declaration_name)) |_| {
                        std.debug.print(
                            "Semantic Error: Value already declared in module scope: {s}\n",
                            .{declaration_name},
                        );
                        return NameResolutionError.ValueAlreadyDeclared;
                    }
                }
                if (node_scope.lookupSymbol(declaration_name)) |_| {
                    std.debug.print(
                        "Semantic Error: Value already declared: {s}\n",
                        .{declaration_name},
                    );
                    return NameResolutionError.ValueAlreadyDeclared;
                }

                try self.resolveNode(declaration.value, node_scope, module_scope, context);
                if (declaration.type_annotation) |type_annotation| {
                    _ = try self.resolveTypeReference(type_annotation, module_scope);
                }

                const declaration_symbol = self.symbol_table.insertSymbol(.{
                    .name = declaration_name,
                    .declared_at = declaration.val_token,
                    .kind = .{
                        .Binding = .{
                            .binding_mutability = switch (declaration.binding_mutability) {
                                .Mutable => symbols.BindingMutability.Mutable,
                                .Immutable => symbols.BindingMutability.Immutable,
                            },
                        },
                    },
                });
                self.symbol_id_by_node_id.put(node.id, declaration_symbol.id) catch unreachable;
                node_scope.insertSymbol(declaration_name, declaration_symbol.id);
            },
            .ItemDefinition => |item_definition| switch (item_definition.item) {
                .Function => |function_definition| {
                    try self.resolveFunctionDefinition(
                        node.id,
                        item_definition.identifier_token.kind.Identifier,
                        &function_definition,
                        module_scope,
                    );
                },
                .Structure => |structure_definition| {
                    try self.resolveStructureDefinition(node.id, item_definition.identifier_token.kind.Identifier, &structure_definition, module_scope);
                },
            },
            .Return => |return_statement| {
                if (return_statement.value) |value| {
                    try self.resolveNode(value, node_scope, module_scope, context);
                }
            },
            .Assignment => |assignment| {
                const assignment_identifier = assignment.identifier_token.kind.Identifier;
                const symbol_id = try NameResolver.getSymbolIdForName(assignment_identifier, node_scope, module_scope);
                const symbol = self.symbol_table.getSymbol(symbol_id);

                switch (symbol.kind) {
                    .Binding => |binding| {
                        if (binding.binding_mutability == symbols.BindingMutability.Immutable) {
                            std.debug.print(
                                "Semantic Error: Cannot assign to immutable variable: {s}\n",
                                .{assignment_identifier},
                            );
                            return NameResolutionError.CannotAssignToImmutable;
                        }
                    },
                    else => {
                        std.debug.print(
                            "Semantic Error: Cannot assign to non-binding symbol: {s}\n",
                            .{assignment_identifier},
                        );
                        return NameResolutionError.UndefinedIdentifier;
                    },
                }
                self.symbol_id_by_node_id.put(node.id, symbol_id) catch unreachable;
                try self.resolveNode(assignment.value, node_scope, module_scope, context);
            },
            .Loop => |loop| {
                var loop_scope = scope.Scope.init(self.allocator, node_scope);
                try self.resolveNode(loop.body_block, &loop_scope, module_scope, context);
            },
            .While => |while_statement| {
                try self.resolveNode(while_statement.condition, node_scope, module_scope, context);
                if (while_statement.update) |update| {
                    try self.resolveNode(update, node_scope, module_scope, context);
                }
                var loop_scope = scope.Scope.init(self.allocator, node_scope);
                try self.resolveNode(while_statement.body_block, &loop_scope, module_scope, context);
            },
            .CallExpression => |call_expression| {
                try self.resolveNode(call_expression.callee, node_scope, module_scope, context);

                for (call_expression.arguments) |*argument| {
                    try self.resolveNode(argument, node_scope, module_scope, context);
                }
            },
            .BinaryExpression => |binaryExpression| {
                try self.resolveNode(binaryExpression.left, node_scope, module_scope, context);
                try self.resolveNode(binaryExpression.right, node_scope, module_scope, context);
            },
            .UnaryExpression => |unaryExpression| {
                try self.resolveNode(unaryExpression.operand, node_scope, module_scope, context);
            },
            .Identifier => |identifier| {
                const identifier_name = identifier.kind.Identifier;
                const symbol_id = try NameResolver.getSymbolIdForName(identifier_name, node_scope, module_scope);
                self.symbol_id_by_node_id.put(node.id, symbol_id) catch unreachable;
            },
            .Block => |block| {
                var block_scope = scope.Scope.init(self.allocator, node_scope);
                for (block.statements) |statement| {
                    try self.resolveNode(&statement, &block_scope, module_scope, context);
                }
                if (block.result) |result_node| {
                    try self.resolveNode(result_node, &block_scope, module_scope, context);
                }
            },
            .IfStatement => |if_statement| {
                try self.resolveNode(if_statement.condition, node_scope, module_scope, context);
                try self.resolveNode(if_statement.then_branch, node_scope, module_scope, context);
            },
            .IfExpression => |if_expression| {
                try self.resolveNode(if_expression.condition, node_scope, module_scope, context);
                try self.resolveNode(if_expression.then_block, node_scope, module_scope, context);
                try self.resolveNode(if_expression.else_block, node_scope, module_scope, context);
            },
            .MatchExpression => |match_expression| {
                if (match_expression.subject) |subject| {
                    try self.resolveNode(subject, node_scope, module_scope, context);
                }
                for (match_expression.arms) |arm| {
                    try self.resolveNode(arm.pattern_or_condition, node_scope, module_scope, context);
                    try self.resolveNode(arm.body, node_scope, module_scope, context);
                }
                if (match_expression.else_arm) |else_arm| {
                    try self.resolveNode(else_arm, node_scope, module_scope, context);
                }
            },
            .ExpressionStatement => |expression_statement| {
                try self.resolveNode(expression_statement.expression, node_scope, module_scope, context);
            },
            .StructureConstruction => |*structure_construction| {
                try self.resolveStructureConstruction(node.id, structure_construction, node_scope, module_scope, context);
            },
            .IntegerLiteral,
            .BooleanLiteral,
            .StringLiteral,
            .Leave,
            .Continue,
            => {},
        }
    }

    fn getSymbolIdForName(
        name: []const u8,
        node_scope: *scope.Scope,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!symbols.SymbolId {
        const symbol_id = node_scope.lookupSymbol(name) orelse module_scope.lookupSymbol(name) orelse {
            std.debug.print(
                "Semantic Error: Undefined identifier: {s}\n",
                .{name},
            );
            return NameResolutionError.UndefinedIdentifier;
        };

        return symbol_id;
    }

    fn resolveStructureConstruction(
        self: *@This(),
        node_id: ast.NodeId,
        structure_construction: *const ast.StructureConstruction,
        node_scope: *scope.Scope,
        module_scope: *scope.ModuleScope,
        context: ResolutionContext,
    ) NameResolutionError!void {
        const structure_name = structure_construction.structure_name.kind.Identifier;
        const symbol_id = module_scope.lookupSymbol(structure_name) orelse {
            std.debug.print(
                "Semantic Error: Undefined structure in structure construction: {s}\n",
                .{structure_name},
            );
            return NameResolutionError.UndefinedIdentifier;
        };
        self.symbol_id_by_node_id.put(node_id, symbol_id) catch unreachable;
        for (structure_construction.fields) |field| {
            try self.resolveNode(field.value, node_scope, module_scope, context);
        }
    }

    fn resolveFunctionDefinition(
        self: *@This(),
        node_id: ast.NodeId,
        function_name: []const u8,
        function_definition: *const ast.Function,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!void {
        var function_scope = scope.Scope.init(self.allocator, null);
        var resolved_parameters = std.ArrayList(symbols.ResolvedParameter){};

        for (function_definition.parameters) |*parameter| {
            const parameter_name = parameter.name.kind.Identifier;
            function_scope.validateNotInScope(parameter_name) catch {
                std.debug.print("Semantic Error: Value already declared in function scope: {s}\n", .{parameter_name});
                return NameResolutionError.ValueAlreadyDeclared;
            };

            const parameter_symbol = self.symbol_table.insertSymbol(.{
                .name = parameter.name.kind.Identifier,
                .declared_at = parameter.name,
                .kind = .{ .Binding = .{ .binding_mutability = symbols.BindingMutability.Mutable } },
            });
            function_scope.insertSymbol(parameter.name.kind.Identifier, parameter_symbol.id);
            resolved_parameters.append(self.allocator, .{
                .symbol_id = parameter_symbol.id,
                .name = parameter_name,
                .type_reference = try self.resolveTypeReference(parameter.type_annotation, module_scope),
            }) catch unreachable;
        }

        const function_symbol_id = module_scope.lookupSymbol(function_name) orelse unreachable;
        const resolved_function = symbols.ResolvedFunction{
            .symbol_id = function_symbol_id,
            .name = function_name,
            .parameters = resolved_parameters.toOwnedSlice(self.allocator) catch unreachable,
            .return_type_reference = try self.resolveTypeReference(function_definition.return_type_annotation, module_scope),
            .implementation = .{
                .user_defined = .{
                    .node_id = node_id,
                    .body_node_id = function_definition.body_expression.id,
                },
            },
        };
        self.appendResolvedItem(.{ .Function = resolved_function });

        try self.resolveNode(function_definition.body_expression, &function_scope, module_scope, .{
            .module_shadowing = .Allowed,
        });
    }

    fn resolveStructureDefinition(
        self: *@This(),
        node_id: ast.NodeId,
        structure_name: []const u8,
        structure_definition: *const ast.Structure,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!void {
        const structure_symbol_id = module_scope.lookupSymbol(structure_name) orelse unreachable;
        var resolved_fields = std.ArrayList(symbols.ResolvedStructureField){};
        for (structure_definition.fields) |field| {
            resolved_fields.append(self.allocator, .{
                .name = field.name.kind.Identifier,
                .type_reference = try self.resolveTypeReference(field.type_annotation, module_scope),
            }) catch unreachable;
        }

        self.appendResolvedItem(.{
            .Structure = .{
                .symbol_id = structure_symbol_id,
                .name = structure_name,
                .fields = resolved_fields.toOwnedSlice(self.allocator) catch unreachable,
                .node_id = node_id,
            },
        });
    }

    fn resolveTypeReference(
        self: *@This(),
        type_annotation: ast.TypeAnnotation,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!symbols.ResolvedTypeReference {
        const type_name = type_annotation.name_token.kind.Identifier;
        const resolved_type_reference: symbols.ResolvedTypeReference = if (builtinTypeFromName(type_name)) |builtin_type|
            .{ .Builtin = builtin_type }
        else block: {
            const symbol_id = module_scope.lookupSymbol(type_name) orelse {
                std.debug.print("Semantic Error: Unknown type annotation: {s}\n", .{type_name});
                return NameResolutionError.UndefinedIdentifier;
            };
            const symbol = self.symbol_table.getSymbol(symbol_id);
            switch (symbol.kind) {
                .Structure => break :block symbols.ResolvedTypeReference{ .Symbol = symbol_id },
                else => {
                    std.debug.print("Semantic Error: Type annotation must reference a structure, got: {s}\n", .{type_name});
                    return NameResolutionError.InvalidTypeAnnotation;
                },
            }
        };

        self.type_reference_by_type_annotation_id.put(
            type_annotation.id,
            resolved_type_reference,
        ) catch unreachable;
        return resolved_type_reference;
    }

    fn appendResolvedItem(self: *@This(), item: symbols.ResolvedItem) void {
        const symbol_id = switch (item) {
            .Function => |function| function.symbol_id,
            .Structure => |structure| structure.symbol_id,
        };
        self.resolved_item_by_symbol_id.put(symbol_id, item) catch unreachable;
    }

    fn builtinTypeFromName(name: []const u8) ?symbols.BuiltinType {
        if (std.mem.eql(u8, name, "unit")) return .Unit;
        if (std.mem.eql(u8, name, "boolean")) return .Boolean;
        if (std.mem.eql(u8, name, "int")) return .Integer;
        if (std.mem.eql(u8, name, "string")) return .String;
        return null;
    }
};
