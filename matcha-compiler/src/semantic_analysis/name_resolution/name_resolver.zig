const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const Scope = @import("scope.zig").Scope;

const NameResolutionError = error{
    UndefinedIdentifier,
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
            .program = program,
            .name_resolution_map = self.resolution_map,
            .symbol_table = self.symbol_table,
        };
    }

    fn resolveNode(self: *@This(), node: *const ast.Node, scope: *Scope) !void {
        switch (node.kind) {
            .ValueDeclaration => |valueDeclaration| {
                try self.resolveNode(valueDeclaration.value, scope);
                const symbol_id = self.next_symbol_id;
                self.next_symbol_id += 1;
                try self.symbol_table.put(symbol_id, .{
                    .id = symbol_id,
                    .name = valueDeclaration.name.kind.Identifier,
                    .declaredAt = valueDeclaration.val_token,
                });
                try self.resolution_map.put(node.id, symbol_id);
                try scope.insertSymbol(valueDeclaration.name.kind.Identifier, symbol_id);
            },
            .BinaryExpression => |binaryExpression| {
                try self.resolveNode(binaryExpression.left, scope);
                try self.resolveNode(binaryExpression.right, scope);
            },
            .UnaryExpression => |unaryExpression| {
                try self.resolveNode(unaryExpression.operand, scope);
            },
            .Identifier => {
                const symbol_id = scope.lookupSymbol(node.kind.Identifier.kind.Identifier);
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
                if (if_statement.else_branch) |else_branch| {
                    try self.resolveNode(else_branch.else_block, scope);
                }
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
