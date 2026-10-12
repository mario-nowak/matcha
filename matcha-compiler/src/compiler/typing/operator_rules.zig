const std = @import("std");
const ast = @import("ast");

const TypeId = @import("type.zig").TypeId;
const TypeStore = @import("type_store.zig").TypeStore;

pub const BinaryOperatorSignature = struct {
    argument_type_id: TypeId,
    return_type_id: TypeId,
};

pub const BinaryOperatorRules = std.EnumArray(ast.BinaryOperator, ?BinaryOperatorSignature);

pub fn getBinaryOperatorRules(type_store: *const TypeStore, operand_type_id: TypeId) ?BinaryOperatorRules {
    return switch (type_store.getType(operand_type_id)) {
        .boolean => BinaryOperatorRules.init(.{
            .@"and" = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .@"or" = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .equal = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .not_equal = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than = null,
            .less_than_or_equal = null,
            .greater_than = null,
            .greater_than_or_equal = null,
            .add = null,
            .subtract = null,
            .multiply = null,
            .divide = null,
        }),
        .integer => BinaryOperatorRules.init(.{
            .add = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .subtract = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .multiply = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .divide = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .equal = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .not_equal = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than_or_equal = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .greater_than = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .greater_than_or_equal = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .@"and" = null,
            .@"or" = null,
        }),
        .string => BinaryOperatorRules.init(.{
            .add = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.string_type_id },
            .equal = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.boolean_type_id },
            .not_equal = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than = null,
            .less_than_or_equal = null,
            .greater_than = null,
            .greater_than_or_equal = null,
            .subtract = null,
            .multiply = null,
            .divide = null,
            .@"and" = null,
            .@"or" = null,
        }),
        .structure, .array => BinaryOperatorRules.init(.{
            .add = null,
            .equal = .{ .argument_type_id = operand_type_id, .return_type_id = type_store.boolean_type_id },
            .not_equal = .{ .argument_type_id = operand_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than = null,
            .less_than_or_equal = null,
            .greater_than = null,
            .greater_than_or_equal = null,
            .subtract = null,
            .multiply = null,
            .divide = null,
            .@"and" = null,
            .@"or" = null,
        }),
        .unit => BinaryOperatorRules.init(.{
            .add = null,
            .equal = .{ .argument_type_id = type_store.unit_type_id, .return_type_id = type_store.boolean_type_id },
            .not_equal = .{ .argument_type_id = type_store.unit_type_id, .return_type_id = type_store.boolean_type_id },
            .less_than = null,
            .less_than_or_equal = null,
            .greater_than = null,
            .greater_than_or_equal = null,
            .subtract = null,
            .multiply = null,
            .divide = null,
            .@"and" = null,
            .@"or" = null,
        }),
        .function,
        .@"union",
        .union_constructor,
        => null,
    };
}

pub const UnaryOperatorSignature = struct {
    return_type_id: TypeId,
};

pub const UnaryOperatorRules = std.EnumArray(ast.UnaryOperator, ?UnaryOperatorSignature);

pub fn getUnaryOperatorRules(type_store: *const TypeStore, operand_type_id: TypeId) ?UnaryOperatorRules {
    return switch (type_store.getType(operand_type_id)) {
        .boolean => UnaryOperatorRules.init(.{
            .negate = null,
            .not = .{ .return_type_id = type_store.boolean_type_id },
        }),
        .integer => UnaryOperatorRules.init(.{
            .negate = .{ .return_type_id = type_store.integer_type_id },
            .not = null,
        }),
        .unit,
        .string,
        .structure,
        .function,
        .array,
        .@"union",
        .union_constructor,
        => null,
    };
}
