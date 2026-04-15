const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const Type = enum {
    Unit,
    Boolean,
    Integer,
    String,
};

pub const BinaryOperatorSignature = struct {
    argument_type: Type,
    return_type: Type,
};
pub const BinaryOperatorRules = std.EnumArray(ast.BinaryOperator, ?BinaryOperatorSignature);
pub const BinaryOperatorRulesByType = std.EnumArray(Type, ?BinaryOperatorRules);
pub const binary_operator_rules_by_type = BinaryOperatorRulesByType.init(.{
    .Unit = null,
    .Boolean = BinaryOperatorRules.init(.{
        .And = .{ .argument_type = .Boolean, .return_type = .Boolean },
        .Or = .{ .argument_type = .Boolean, .return_type = .Boolean },
        .Equal = .{ .argument_type = .Boolean, .return_type = .Boolean },
        .NotEqual = .{ .argument_type = .Boolean, .return_type = .Boolean },
        .LessThan = null,
        .LessThanOrEqual = null,
        .GreaterThan = null,
        .GreaterThanOrEqual = null,
        .Add = null,
        .Subtract = null,
        .Multiply = null,
        .Divide = null,
    }),
    .Integer = BinaryOperatorRules.init(.{
        .Add = .{ .argument_type = .Integer, .return_type = .Integer },
        .Subtract = .{ .argument_type = .Integer, .return_type = .Integer },
        .Multiply = .{ .argument_type = .Integer, .return_type = .Integer },
        .Divide = .{ .argument_type = .Integer, .return_type = .Integer },
        .Equal = .{ .argument_type = .Integer, .return_type = .Boolean },
        .NotEqual = .{ .argument_type = .Integer, .return_type = .Boolean },
        .LessThan = .{ .argument_type = .Integer, .return_type = .Boolean },
        .LessThanOrEqual = .{ .argument_type = .Integer, .return_type = .Boolean },
        .GreaterThan = .{ .argument_type = .Integer, .return_type = .Boolean },
        .GreaterThanOrEqual = .{ .argument_type = .Integer, .return_type = .Boolean },
        .And = null,
        .Or = null,
    }),
    .String = null,
});

pub const UnaryOperatorSignature = struct {
    return_type: Type,
};
pub const UnaryOperatorRules = std.EnumArray(ast.UnaryOperator, ?UnaryOperatorSignature);
pub const UnaryOperatorRulesByType = std.EnumArray(Type, ?UnaryOperatorRules);
pub const unary_operator_rules_by_type = UnaryOperatorRulesByType.init(.{
    .Unit = null,
    .Boolean = UnaryOperatorRules.init(.{
        .Negate = null,
        .Not = .{ .return_type = .Boolean },
    }),
    .Integer = UnaryOperatorRules.init(.{
        .Negate = .{ .return_type = .Integer },
        .Not = null,
    }),
    .String = null,
});

pub const TypeBySymbolId = std.AutoHashMap(symbols.SymbolId, Type);
pub const TypeByNodeId = std.AutoHashMap(ast.NodeId, Type);

pub const TypedProgram = struct {
    resolved_program: symbols.ResolvedProgram,
    type_by_symbol_id: TypeBySymbolId,
    type_by_node_id: TypeByNodeId,
};
