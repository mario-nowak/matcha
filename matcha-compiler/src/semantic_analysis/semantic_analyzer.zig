const std = @import("std");
const abstract_syntax_tree = @import("../abstract_syntax_tree.zig");
const Scope = @import("scope.zig").Scope;
const Symbol = @import("scope.zig").Symbol;
const Program = abstract_syntax_tree.Program;
const Node = abstract_syntax_tree.Node;

const SemanticError = error{
    UndefinedIdentifier,
};

pub const SemanticAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn validateProgram(self: *@This(), program: *const Program) !void {
        var scope = Scope.init(self.allocator, null);
        for (program.statements) |statement| {
            try self.validateNode(&statement, &scope);
        }
    }

    fn validateNode(self: *const @This(), node: *const Node, scope: *Scope) !void {
        switch (node.*) {
            .ValueDeclaration => |valueDeclaration| {
                // Here you can add checks for the value declaration
                try self.validateNode(valueDeclaration.value, scope);
                const symbol: *Symbol = try self.allocator.create(Symbol);
                symbol.* = .{ .declaredAt = valueDeclaration.val_token };
                try scope.insertSymbol(valueDeclaration.name.type.Identifier, symbol);
            },
            .BinaryExpression => |binaryExpression| {
                try self.validateNode(binaryExpression.left, scope);
                try self.validateNode(binaryExpression.right, scope);
            },
            .UnaryExpression => |unaryExpression| {
                try self.validateNode(unaryExpression.operand, scope);
            },
            .Identifier => {
                const symbol = scope.lookupSymbol(node.Identifier.type.Identifier);
                if (symbol == null) {
                    std.debug.print("Semantic Error: Undefined identifier: {s}\n", .{node.Identifier.type.Identifier});
                    return SemanticError.UndefinedIdentifier;
                }
            },
            .Integer => {
                // Integers are valid by default
            },
            .Block => |block| {
                var block_scope = Scope.init(self.allocator, scope);
                for (block.statements) |statement| {
                    try self.validateNode(&statement, &block_scope);
                }
                if (block.result) |result_node| {
                    try self.validateNode(result_node, &block_scope);
                }
            },
            else => {
                // Leave blank for now
            },
        }
    }
};
