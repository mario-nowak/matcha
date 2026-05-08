const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const type_expressions = @import("type_expressions");
const scope = @import("scope.zig");

pub const NameResolutionError = error{
    UndefinedIdentifier,
    InvalidTypeAnnotation,
    ValueAlreadyDeclared,
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

const FunctionResolutionTarget = struct {
    node_id: ast.NodeId,
    symbol: symbols.Symbol,
};

pub const NameResolver = struct {
    allocator: std.mem.Allocator,
    symbol_table: symbols.SymbolTable,
    symbol_id_by_node_id: symbols.SymbolIdByNodeId,
    resolved_function_by_symbol_id: symbols.ResolvedFunctionBySymbolId,
    resolved_structure_by_symbol_id: symbols.ResolvedStructureBySymbolId,
    annotated_type_reference_by_symbol_id: symbols.AnnotatedTypeReferenceBySymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_table = symbols.SymbolTable.init(allocator),
            .symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(allocator),
            .resolved_function_by_symbol_id = symbols.ResolvedFunctionBySymbolId.init(allocator),
            .resolved_structure_by_symbol_id = symbols.ResolvedStructureBySymbolId.init(allocator),
            .annotated_type_reference_by_symbol_id = symbols.AnnotatedTypeReferenceBySymbolId.init(allocator),
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
        self.resolved_function_by_symbol_id = symbols.ResolvedFunctionBySymbolId.init(self.allocator);
        self.resolved_structure_by_symbol_id = symbols.ResolvedStructureBySymbolId.init(self.allocator);
        self.annotated_type_reference_by_symbol_id = symbols.AnnotatedTypeReferenceBySymbolId.init(self.allocator);

        var module_scope = try self.buildModuleScope(program);

        self.addPrintIntBuiltinDebuggingFunction(&module_scope);
        self.addPrintStringBuiltinDebuggingFunction(&module_scope);
        self.addReadFileBuiltinFunction(&module_scope);

        for (program.statements) |statement| {
            try self.resolveNode(&statement, &root_scope, &module_scope, .{
                .module_shadowing = .Forbidden,
            });
        }

        return .{
            .program = program.*,
            .symbol_id_by_node_id = self.symbol_id_by_node_id,
            .symbol_table = self.symbol_table,
            .resolved_function_by_symbol_id = self.resolved_function_by_symbol_id,
            .resolved_structure_by_symbol_id = self.resolved_structure_by_symbol_id,
            .annotated_type_reference_by_symbol_id = self.annotated_type_reference_by_symbol_id,
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
        self.appendResolvedFunction(.{
            .symbol_id = print_int_symbol.id,
            .name = print_int_symbol.name,
            .parameters = self.allocator.dupe(symbols.ResolvedParameter, &.{.{
                .symbol_id = parameter_symbol.id,
                .name = parameter_symbol.name,
                .type_reference = .{ .Builtin = .Integer },
            }}) catch unreachable,
            .return_type_reference = .{ .Builtin = .Unit },
            .implementation = .builtin,
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
        self.appendResolvedFunction(.{
            .symbol_id = print_string_symbol.id,
            .name = print_string_symbol.name,
            .parameters = self.allocator.dupe(symbols.ResolvedParameter, &.{.{
                .symbol_id = parameter_symbol.id,
                .name = parameter_symbol.name,
                .type_reference = .{ .Builtin = .String },
            }}) catch unreachable,
            .return_type_reference = .{ .Builtin = .Unit },
            .implementation = .builtin,
        });
    }

    fn addReadFileBuiltinFunction(self: *@This(), module_scope: *scope.ModuleScope) void {
        const read_file_symbol = self.symbol_table.insertSymbol(.{
            .name = "readFile",
            .declared_at = null,
            .kind = .{ .Function = .{ .implementation = .BuiltinReadFile } },
        });
        module_scope.insertSymbol(read_file_symbol.name, read_file_symbol.id);
        const parameter_symbol = self.symbol_table.insertSymbol(.{
            .name = "path",
            .declared_at = null,
            .kind = .{ .Binding = .{ .binding_mutability = symbols.BindingMutability.Immutable } },
        });
        self.appendResolvedFunction(.{
            .symbol_id = read_file_symbol.id,
            .name = read_file_symbol.name,
            .parameters = self.allocator.dupe(symbols.ResolvedParameter, &.{.{
                .symbol_id = parameter_symbol.id,
                .name = parameter_symbol.name,
                .type_reference = .{ .Builtin = .String },
            }}) catch unreachable,
            .return_type_reference = .{ .Builtin = .String },
            .implementation = .builtin,
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
                const annotated_type_reference = if (declaration.type_annotation) |type_annotation|
                    try self.resolveTypeExpression(type_annotation, module_scope)
                else
                    null;

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
                if (annotated_type_reference) |type_reference| {
                    self.annotated_type_reference_by_symbol_id.put(
                        declaration_symbol.id,
                        type_reference,
                    ) catch unreachable;
                }
            },
            .ItemDefinition => |item_definition| switch (item_definition.item) {
                .Function => |function_definition| {
                    const function_symbol_id = module_scope.lookupSymbol(
                        item_definition.identifier_token.kind.Identifier,
                    ) orelse unreachable;
                    const function_symbol = self.symbol_table.getSymbol(function_symbol_id);
                    const resolved_function = try self.resolveFunction(
                        .{
                            .node_id = node.id,
                            .symbol = function_symbol,
                        },
                        &function_definition,
                        module_scope,
                    );
                    self.appendResolvedFunction(resolved_function);
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
                try self.resolveNode(assignment.target, node_scope, module_scope, context);
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
            .MemberAccess => |member_access| {
                try self.resolveNode(member_access.base, node_scope, module_scope, context);
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
            .ArrayLiteral => |array_literal| {
                for (array_literal.elements) |*element| {
                    try self.resolveNode(element, node_scope, module_scope, context);
                }
            },
            .IndexAccess => |index_access| {
                try self.resolveNode(index_access.base, node_scope, module_scope, context);
                try self.resolveNode(index_access.index, node_scope, module_scope, context);
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

    fn resolveFunction(
        self: *@This(),
        target: FunctionResolutionTarget,
        function_definition: *const ast.Function,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!symbols.ResolvedFunction {
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
                .type_reference = try self.resolveTypeExpression(parameter.type_annotation, module_scope),
            }) catch unreachable;
        }

        const resolved_function = symbols.ResolvedFunction{
            .symbol_id = target.symbol.id,
            .name = target.symbol.name,
            .parameters = resolved_parameters.toOwnedSlice(self.allocator) catch unreachable,
            .return_type_reference = try self.resolveTypeExpression(function_definition.return_type_annotation, module_scope),
            .implementation = .{
                .user_defined = .{
                    .node_id = target.node_id,
                    .body_node_id = function_definition.body_expression.id,
                },
            },
        };

        try self.resolveNode(function_definition.body_expression, &function_scope, module_scope, .{
            .module_shadowing = .Allowed,
        });

        return resolved_function;
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
                .type_reference = try self.resolveTypeExpression(field.type_annotation, module_scope),
            }) catch unreachable;
        }

        var function_symbol_ids = std.ArrayList(symbols.SymbolId){};
        for (structure_definition.function_definitions) |*node| {
            switch (node.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function_definition| {
                        const method_symbol = self.symbol_table.insertSymbol(.{
                            .name = item_definition.identifier_token.kind.Identifier,
                            .declared_at = item_definition.item_token,
                            .kind = .{ .Function = .{ .implementation = .UserDefined } },
                        });
                        self.symbol_id_by_node_id.put(node.id, method_symbol.id) catch unreachable;
                        const resolved_function = try self.resolveFunction(
                            .{
                                .node_id = node.id,
                                .symbol = method_symbol,
                            },
                            &function_definition,
                            module_scope,
                        );
                        self.appendResolvedFunction(resolved_function);
                        function_symbol_ids.append(self.allocator, method_symbol.id) catch unreachable;
                    },
                    else => unreachable,
                },
                else => unreachable,
            }
        }

        self.appendResolvedStructure(.{
            .symbol_id = structure_symbol_id,
            .name = structure_name,
            .fields = resolved_fields.toOwnedSlice(self.allocator) catch unreachable,
            .function_symbol_ids = function_symbol_ids.toOwnedSlice(self.allocator) catch unreachable,
            .node_id = node_id,
        });
    }

    fn resolveTypeExpression(
        self: *@This(),
        type_expression: *const type_expressions.TypeExpression,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!symbols.ResolvedTypeReference {
        return switch (type_expression.*) {
            .Named => |named_type_expression| block: {
                const type_name = named_type_expression.name_token.kind.Identifier;
                break :block if (builtinTypeFromName(type_name)) |builtin_type|
                    .{ .Builtin = builtin_type }
                else named_type_reference: {
                    const symbol_id = module_scope.lookupSymbol(type_name) orelse {
                        std.debug.print("Semantic Error: Unknown type annotation: {s}\n", .{type_name});
                        return NameResolutionError.UndefinedIdentifier;
                    };
                    const symbol = self.symbol_table.getSymbol(symbol_id);
                    switch (symbol.kind) {
                        .Structure => break :named_type_reference symbols.ResolvedTypeReference{ .Symbol = symbol_id },
                        else => {
                            std.debug.print("Semantic Error: Type annotation must reference a structure, got: {s}\n", .{type_name});
                            return NameResolutionError.InvalidTypeAnnotation;
                        },
                    }
                };
            },
            .Array => |array_type_expression| block: {
                const array_type_reference = self.allocator.create(symbols.ResolvedTypeReference) catch unreachable;
                array_type_reference.* = try self.resolveTypeExpression(array_type_expression.element_type, module_scope);

                break :block .{ .Array = array_type_reference };
            },
        };
    }

    fn appendResolvedFunction(self: *@This(), function: symbols.ResolvedFunction) void {
        self.resolved_function_by_symbol_id.put(function.symbol_id, function) catch unreachable;
    }

    fn appendResolvedStructure(self: *@This(), structure: symbols.ResolvedStructure) void {
        self.resolved_structure_by_symbol_id.put(structure.symbol_id, structure) catch unreachable;
    }

    fn builtinTypeFromName(name: []const u8) ?symbols.BuiltinType {
        if (std.mem.eql(u8, name, "unit")) return .Unit;
        if (std.mem.eql(u8, name, "boolean")) return .Boolean;
        if (std.mem.eql(u8, name, "int")) return .Integer;
        if (std.mem.eql(u8, name, "string")) return .String;
        return null;
    }
};
