const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const Type = enum {
    Unit,
    Boolean,
    Integer,
};

pub const BinaryOperatorSignature = struct {
    argument_type: Type,
    return_type: Type,
};
pub const BinaryOperatorRules = std.EnumArray(ast.BinaryOperator, ?BinaryOperatorSignature);
pub const BinaryOperatorRulesByType = std.EnumArray(Type, ?BinaryOperatorRules);
pub const binary_operator_rules_by_type = BinaryOperatorRulesByType.init(.{
    .Unit = null,
    .Boolean = null,
    .Integer = BinaryOperatorRules.init(.{
        .Add = .{ .argument_type = .Integer, .return_type = .Integer },
        .Subtract = .{ .argument_type = .Integer, .return_type = .Integer },
        .Multiply = .{ .argument_type = .Integer, .return_type = .Integer },
        .Divide = .{ .argument_type = .Integer, .return_type = .Integer },
    }),
});

pub const UnaryOperatorSignature = struct {
    return_type: Type,
};
pub const UnaryOperatorRules = std.EnumArray(ast.UnaryOperator, ?UnaryOperatorSignature);
pub const UnaryOperatorRulesByType = std.EnumArray(Type, ?UnaryOperatorRules);
pub const unary_operator_rules_by_type = UnaryOperatorRulesByType.init(.{
    .Unit = null,
    .Boolean = null,
    .Integer = UnaryOperatorRules.init(.{
        .Negate = .{ .return_type = .Integer },
    }),
});

pub const SymbolTypeMap = std.AutoHashMap(symbols.SymbolId, Type);
pub const NodeTypeMap = std.AutoHashMap(ast.NodeId, Type);

pub const TypedProgram = struct {
    resolved_program: symbols.ResolvedProgram,
    symbol_type_map: SymbolTypeMap,
    node_type_map: NodeTypeMap,
};
