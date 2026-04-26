const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const TypeId = u32;
pub const StructureTypeId = u32;
pub const TaggedUnionTypeId = u32;

pub const Type = union(enum) {
    Unit,
    Boolean,
    Integer,
    String,

    Structure: StructureTypeId,
    Array: TypeId,
    TaggedUnion: TaggedUnionTypeId,
};

pub const TypeStore = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(Type),
    structure_types: std.ArrayList(StructureType),
    unit_type_id: TypeId,
    boolean_type_id: TypeId,
    integer_type_id: TypeId,
    string_type_id: TypeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        var store = @This(){
            .allocator = allocator,
            .types = .{},
            .unit_type_id = undefined,
            .boolean_type_id = undefined,
            .integer_type_id = undefined,
            .string_type_id = undefined,
            .structure_types = .{},
        };

        store.unit_type_id = store.addType(.Unit);
        store.boolean_type_id = store.addType(.Boolean);
        store.integer_type_id = store.addType(.Integer);
        store.string_type_id = store.addType(.String);

        return store;
    }

    pub fn addType(self: *@This(), matcha_type: Type) TypeId {
        const type_id: TypeId = @intCast(self.types.items.len);
        self.types.append(self.allocator, matcha_type) catch unreachable;
        return type_id;
    }

    pub fn addStructureType(self: *@This(), structure_type: StructureType) StructureTypeId {
        const structure_type_id: StructureTypeId = @intCast(self.structure_types.items.len);
        self.structure_types.append(self.allocator, structure_type) catch unreachable;
        return self.addType(.{ .Structure = structure_type_id });
    }

    pub fn getType(self: *const @This(), type_id: TypeId) Type {
        return self.types.items[type_id];
    }
};

pub const StructureType = struct {
    name: []const u8,
    fields: []const Field,
    field_index_by_name: std.StringHashMap(u32),
};

pub const Field = struct {
    name: []const u8,
    type_id: TypeId,
};

pub const StructureConstructionLayout = struct {
    field_indices: []const u32,
};

pub const BinaryOperatorSignature = struct {
    argument_type_id: TypeId,
    return_type_id: TypeId,
};
pub const BinaryOperatorRules = std.EnumArray(ast.BinaryOperator, ?BinaryOperatorSignature);

pub fn getBinaryOperatorRules(type_store: *const TypeStore, operand_type_id: TypeId) ?BinaryOperatorRules {
    return switch (type_store.getType(operand_type_id)) {
        .Boolean => BinaryOperatorRules.init(.{
            .And = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .Or = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .Equal = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .NotEqual = .{ .argument_type_id = type_store.boolean_type_id, .return_type_id = type_store.boolean_type_id },
            .LessThan = null,
            .LessThanOrEqual = null,
            .GreaterThan = null,
            .GreaterThanOrEqual = null,
            .Add = null,
            .Subtract = null,
            .Multiply = null,
            .Divide = null,
        }),
        .Integer => BinaryOperatorRules.init(.{
            .Add = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .Subtract = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .Multiply = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .Divide = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.integer_type_id },
            .Equal = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .NotEqual = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .LessThan = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .LessThanOrEqual = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .GreaterThan = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .GreaterThanOrEqual = .{ .argument_type_id = type_store.integer_type_id, .return_type_id = type_store.boolean_type_id },
            .And = null,
            .Or = null,
        }),
        .Unit,
        .String,
        .Structure,
        .Array,
        .TaggedUnion,
        => null,
    };
}

pub const UnaryOperatorSignature = struct {
    return_type_id: TypeId,
};
pub const UnaryOperatorRules = std.EnumArray(ast.UnaryOperator, ?UnaryOperatorSignature);

pub fn getUnaryOperatorRules(type_store: *const TypeStore, operand_type_id: TypeId) ?UnaryOperatorRules {
    return switch (type_store.getType(operand_type_id)) {
        .Boolean => UnaryOperatorRules.init(.{
            .Negate = null,
            .Not = .{ .return_type_id = type_store.boolean_type_id },
        }),
        .Integer => UnaryOperatorRules.init(.{
            .Negate = .{ .return_type_id = type_store.integer_type_id },
            .Not = null,
        }),
        .Unit,
        .String,
        .Structure,
        .Array,
        .TaggedUnion,
        => null,
    };
}

pub const TypeBySymbolId = std.AutoHashMap(symbols.SymbolId, TypeId);
pub const TypeByNodeId = std.AutoHashMap(ast.NodeId, TypeId);
pub const StructureConstructionLayoutByNodeId = std.AutoHashMap(ast.NodeId, StructureConstructionLayout);

pub const TypedProgram = struct {
    resolved_program: symbols.ResolvedProgram,
    type_store: TypeStore,
    type_by_symbol_id: TypeBySymbolId,
    type_by_node_id: TypeByNodeId,
    structure_construction_layout_by_node_id: StructureConstructionLayoutByNodeId,
};
