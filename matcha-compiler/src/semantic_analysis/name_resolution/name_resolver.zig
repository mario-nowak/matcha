const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const scope = @import("scope.zig");

pub const NameResolutionError = error{
    UndefinedIdentifier,
    ValueAlreadyDeclared,
    CannotAssignToImmutable,
    FunctionAlreadyDefined,
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
    parameter_symbol_ids_by_function_symbol_id: symbols.ParameterSymbolIdsByFunctionSymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_table = symbols.SymbolTable.init(allocator),
            .symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(allocator),
            .parameter_symbol_ids_by_function_symbol_id = symbols.ParameterSymbolIdsByFunctionSymbolId.init(allocator),
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
        self.parameter_symbol_ids_by_function_symbol_id = symbols.ParameterSymbolIdsByFunctionSymbolId.init(self.allocator);

        var module_scope = try self.buildModuleScope(program);

        self.addPrintIntBuiltinDebuggingFunction(&module_scope);

        for (program.statements) |statement| {
            try self.resolveNode(&statement, &root_scope, &module_scope, .{
                .module_shadowing = .Forbidden,
            });
        }

        return .{
            .program = program.*,
            .symbol_id_by_node_id = self.symbol_id_by_node_id,
            .symbol_table = self.symbol_table,
            .parameter_symbol_ids_by_function_symbol_id = self.parameter_symbol_ids_by_function_symbol_id,
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
        self.parameter_symbol_ids_by_function_symbol_id.put(
            print_int_symbol.id,
            self.allocator.dupe(symbols.SymbolId, &.{parameter_symbol.id}) catch unreachable,
        ) catch unreachable;
    }

    fn buildModuleScope(self: *@This(), program: *const ast.Program) NameResolutionError!scope.ModuleScope {
        var module_scope = scope.ModuleScope.init(self.allocator, null);

        for (program.statements) |*statement| {
            switch (statement.kind) {
                .FunctionDefinition => |function_definition| {
                    const function_name = function_definition.identifier_token.kind.Identifier;
                    module_scope.validateNotInScope(function_name) catch {
                        std.debug.print("Semantic Error: Function already defined in module scope: {s}\n", .{function_name});
                        return NameResolutionError.FunctionAlreadyDefined;
                    };

                    const function_symbol = self.symbol_table.insertSymbol(.{
                        .name = function_name,
                        .declared_at = function_definition.item_token,
                        .kind = .{ .Function = .{ .implementation = .UserDefined } },
                    });
                    self.symbol_id_by_node_id.put(statement.id, function_symbol.id) catch unreachable;
                    module_scope.insertSymbol(
                        function_name,
                        function_symbol.id,
                    );
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
            .FunctionDefinition => |function_definition| {
                try self.resolveFunctionDefinition(&function_definition, module_scope);
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
            .ExpressionStatement => |expression_statement| {
                try self.resolveNode(expression_statement.expression, node_scope, module_scope, context);
            },
            .IntegerLiteral,
            .BooleanLiteral,
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

    fn resolveFunctionDefinition(
        self: *@This(),
        function_definition: *const ast.FunctionDefinition,
        module_scope: *scope.ModuleScope,
    ) NameResolutionError!void {
        var function_scope = scope.Scope.init(self.allocator, null);
        var parameter_symbol_ids = std.ArrayList(symbols.SymbolId){};

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
            parameter_symbol_ids.append(self.allocator, parameter_symbol.id) catch unreachable;
            function_scope.insertSymbol(parameter.name.kind.Identifier, parameter_symbol.id);
        }

        const function_name = function_definition.identifier_token.kind.Identifier;
        const function_symbol_id = module_scope.lookupSymbol(function_name) orelse unreachable;
        self.parameter_symbol_ids_by_function_symbol_id.put(
            function_symbol_id,
            parameter_symbol_ids.toOwnedSlice(self.allocator) catch unreachable,
        ) catch unreachable;

        try self.resolveNode(function_definition.body_expression, &function_scope, module_scope, .{
            .module_shadowing = .Allowed,
        });
    }
};
