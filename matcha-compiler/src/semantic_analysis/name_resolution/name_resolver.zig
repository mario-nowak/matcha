const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const Scope = @import("scope.zig").Scope;

const NameResolutionError = error{
    UndefinedIdentifier,
    ValueAlreadyDeclared,
    CannotAssignToImmutable,
};

pub const NameResolver = struct {
    allocator: std.mem.Allocator,
    symbol_table: symbols.SymbolTable,
    resolution_map: symbols.NameResolutionMap,
    next_symbol_id: symbols.SymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_table = symbols.SymbolTable.init(allocator),
            .resolution_map = symbols.NameResolutionMap.init(allocator),
            .next_symbol_id = 0,
        };
    }

    pub fn resolve(self: *@This(), program: *const ast.Program) !symbols.ResolvedProgram {
        var root_scope = Scope.init(self.allocator, null);
        self.symbol_table = symbols.SymbolTable.init(self.allocator);
        self.resolution_map = symbols.NameResolutionMap.init(self.allocator);

        for (program.statements) |statement| {
            try self.resolveNode(&statement, &root_scope);
        }

        return .{
            .program = program.*,
            .name_resolution_map = self.resolution_map,
            .symbol_table = self.symbol_table,
        };
    }

    pub fn generateSymbolId(self: *@This()) symbols.SymbolId {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;

        return symbol_id;
    }

    fn resolveNode(self: *@This(), node: *const ast.Node, scope: *Scope) !void {
        switch (node.kind) {
            .Declaration => |value_declaration| {
                const existing_symbol_id = scope.lookupSymbol(value_declaration.name.kind.Identifier);
                if (existing_symbol_id) |_| {
                    std.debug.print("Semantic Error: Value already declared: {s}\n", .{value_declaration.name.kind.Identifier});
                    return NameResolutionError.ValueAlreadyDeclared;
                }
                try self.resolveNode(value_declaration.value, scope);
                const symbol_id = self.generateSymbolId();
                try self.symbol_table.put(symbol_id, .{
                    .id = symbol_id,
                    .name = value_declaration.name.kind.Identifier,
                    .declaredAt = value_declaration.val_token,
                    .binding_mutability = switch (value_declaration.binding_mutability) {
                        .Mutable => symbols.BindingMutability.Mutable,
                        .Immutable => symbols.BindingMutability.Immutable,
                    },
                });
                try self.resolution_map.put(node.id, symbol_id);
                try scope.insertSymbol(value_declaration.name.kind.Identifier, symbol_id);
            },
            .Assignment => |assignment| {
                const symbol_id = scope.lookupSymbol(assignment.identifier_token.kind.Identifier);
                if (symbol_id) |id| {
                    const symbol = self.symbol_table.get(id).?;
                    if (symbol.binding_mutability == symbols.BindingMutability.Immutable) {
                        std.debug.print("Semantic Error: Cannot assign to immutable variable: {s}\n", .{assignment.identifier_token.kind.Identifier});
                        return NameResolutionError.CannotAssignToImmutable;
                    }

                    try self.resolution_map.put(node.id, id);
                } else {
                    std.debug.print("Semantic Error: Undefined identifier: {s}\n", .{assignment.identifier_token.kind.Identifier});
                    return NameResolutionError.UndefinedIdentifier;
                }
                try self.resolveNode(assignment.value, scope);
            },
            .CallExpression => |call_expression| {
                switch (call_expression.callee.kind) {
                    .Identifier => |identifier| {
                        // -- Debugging --
                        if (!std.mem.eql(u8, identifier.kind.Identifier, "printInt")) {
                            try self.resolveNode(call_expression.callee, scope);
                        }
                    },
                    else => try self.resolveNode(call_expression.callee, scope),
                }

                for (call_expression.arguments) |*argument| {
                    try self.resolveNode(argument, scope);
                }
            },
            .BinaryExpression => |binaryExpression| {
                try self.resolveNode(binaryExpression.left, scope);
                try self.resolveNode(binaryExpression.right, scope);
            },
            .UnaryExpression => |unaryExpression| {
                try self.resolveNode(unaryExpression.operand, scope);
            },
            .Identifier => |identifier| {
                const symbol_id = scope.lookupSymbol(identifier.kind.Identifier);
                if (symbol_id) |id| {
                    try self.resolution_map.put(node.id, id);
                } else {
                    std.debug.print("Semantic Error: Undefined identifier: {s}\n", .{node.kind.Identifier.kind.Identifier});
                    return NameResolutionError.UndefinedIdentifier;
                }
            },
            .IntegerLiteral => {},
            .BooleanLiteral => {},
            .Block => |block| {
                var block_scope = Scope.init(self.allocator, scope);
                for (block.statements) |statement| {
                    try self.resolveNode(&statement, &block_scope);
                }
                if (block.result) |result_node| {
                    try self.resolveNode(result_node, &block_scope);
                }
            },
            .IfStatement => |if_statement| {
                try self.resolveNode(if_statement.condition, scope);
                try self.resolveNode(if_statement.then_branch, scope);
            },
            .IfExpression => |if_expression| {
                try self.resolveNode(if_expression.condition, scope);
                try self.resolveNode(if_expression.then_block, scope);
                try self.resolveNode(if_expression.else_block, scope);
            },
            .ExpressionStatement => |expression_statement| {
                try self.resolveNode(expression_statement.expression, scope);
            },
        }
    }
};
