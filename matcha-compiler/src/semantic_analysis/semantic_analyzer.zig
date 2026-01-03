const std = @import("std");
const abstract_syntax_tree = @import("../abstract_syntax_tree.zig");
const Scope = @import("scope.zig").Scope;
const Symbol = @import("scope.zig").Symbol;
const Program = abstract_syntax_tree.Program;
const Node = abstract_syntax_tree.Node;

const SemanticError = error{
    UndefinedIdentifier,
    BlockMustProduceValue,
    BlockCannotProduceValue,
};

const ValidationContext = struct {
    scope: *Scope,
    requiresValue: bool,
};

pub const SemanticAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn validateProgram(self: *@This(), program: *const Program) !void {
        var root_scope = Scope.init(self.allocator, null);
        var context = ValidationContext{
            .scope = &root_scope,
            .requiresValue = false,
        };
        for (program.statements) |statement| {
            try self.validateNode(&statement, &context);
        }
    }

    fn validateNode(self: *const @This(), node: *const Node, context: *ValidationContext) !void {
        switch (node.*) {
            .ValueDeclaration => |valueDeclaration| {
                // Here you can add checks for the value declaration
                var value_context = ValidationContext{
                    .scope = context.scope,
                    .requiresValue = true,
                };
                try self.validateNode(valueDeclaration.value, &value_context);
                const symbol: *Symbol = try self.allocator.create(Symbol);
                symbol.* = .{ .declaredAt = valueDeclaration.val_token };
                try context.scope.insertSymbol(valueDeclaration.name.type.Identifier, symbol);
            },
            .BinaryExpression => |binaryExpression| {
                var expr_context = ValidationContext{
                    .scope = context.scope,
                    .requiresValue = true,
                };
                try self.validateNode(binaryExpression.left, &expr_context);
                try self.validateNode(binaryExpression.right, &expr_context);
            },
            .UnaryExpression => |unaryExpression| {
                var expr_context = ValidationContext{
                    .scope = context.scope,
                    .requiresValue = true,
                };
                try self.validateNode(unaryExpression.operand, &expr_context);
            },
            .Identifier => {
                const symbol = context.scope.lookupSymbol(node.Identifier.type.Identifier);
                if (symbol == null) {
                    std.debug.print("Semantic Error: Undefined identifier: {s}\n", .{node.Identifier.type.Identifier});
                    return SemanticError.UndefinedIdentifier;
                }
            },
            .Integer => {
                // Integers are valid by default
            },
            .Block => |block| {
                // Validate that block produces a value when required, and doesn't when not required
                if (context.requiresValue and block.result == null) {
                    std.debug.print("Semantic Error: Block must produce a value in this context\n", .{});
                    return SemanticError.BlockMustProduceValue;
                }
                if (!context.requiresValue and block.result != null) {
                    std.debug.print("Semantic Error: Block cannot have a trailing expression in statement context\n", .{});
                    return SemanticError.BlockCannotProduceValue;
                }

                var block_scope = Scope.init(self.allocator, context.scope);
                var statement_context = ValidationContext{
                    .scope = &block_scope,
                    .requiresValue = false,
                };
                for (block.statements) |statement| {
                    try self.validateNode(&statement, &statement_context);
                }
                if (block.result) |result_node| {
                    var result_context = ValidationContext{
                        .scope = &block_scope,
                        .requiresValue = true,
                    };
                    try self.validateNode(result_node, &result_context);
                }
            },
            else => {
                // Leave blank for now
            },
        }
    }
};
