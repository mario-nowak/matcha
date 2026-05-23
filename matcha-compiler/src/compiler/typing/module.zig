const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const TypeId = u32;
pub const StructureTypeId = u32;
pub const FunctionTypeId = u32;
pub const TaggedUnionTypeId = u32;

pub const Type = union(enum) {
    Unit,
    Boolean,
    Integer,
    String,

    Structure: StructureTypeId,
    Function: FunctionTypeId,
    Array: TypeId,
    TaggedUnion: TaggedUnionTypeId,

    pub fn name(self: @This(), store: *const TypeStore, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .Unit => allocator.dupe(u8, "unit"),
            .Boolean => allocator.dupe(u8, "boolean"),
            .Integer => allocator.dupe(u8, "int"),
            .String => allocator.dupe(u8, "string"),
            .Structure => |structure_type_id| allocator.dupe(u8, store.structure_types.items[structure_type_id].name),
            .Array => |element_type_id| std.fmt.allocPrint(allocator, "{s}[]", .{try store.getType(element_type_id).name(store, allocator)}),
            .Function => |function_type_id| {
                const function_type = store.function_types.items[function_type_id];
                var parameter_text = std.ArrayList(u8){};
                defer parameter_text.deinit(allocator);
                for (function_type.parameter_types, 0..) |parameter_type_id, index| {
                    if (index > 0) {
                        try parameter_text.appendSlice(allocator, ", ");
                    }
                    try parameter_text.appendSlice(allocator, try store.getType(parameter_type_id).name(store, allocator));
                }
                return std.fmt.allocPrint(
                    allocator,
                    "function taking ({s}) and returning {s}",
                    .{ parameter_text.items, try store.getType(function_type.return_type).name(store, allocator) },
                );
            },
            .TaggedUnion => allocator.dupe(u8, "tagged union"),
        };
    }
};

pub const TypeStore = struct {
    allocator: std.mem.Allocator,
    types: std.ArrayList(Type),
    structure_types: std.ArrayList(StructureType),
    function_types: std.ArrayList(FunctionType),
    array_type_id_by_element_type_id: std.AutoHashMap(TypeId, TypeId),
    unit_type_id: TypeId,
    boolean_type_id: TypeId,
    integer_type_id: TypeId,
    string_type_id: TypeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        var store = @This(){
            .allocator = allocator,
            .types = .{},
            .array_type_id_by_element_type_id = std.AutoHashMap(TypeId, TypeId).init(allocator),
            .unit_type_id = undefined,
            .boolean_type_id = undefined,
            .integer_type_id = undefined,
            .string_type_id = undefined,
            .structure_types = .{},
            .function_types = .{},
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

    pub fn addStructureType(self: *@This(), structure_type: StructureType) TypeId {
        const structure_type_id: StructureTypeId = @intCast(self.structure_types.items.len);
        self.structure_types.append(self.allocator, structure_type) catch unreachable;
        return self.addType(.{ .Structure = structure_type_id });
    }

    pub fn addFunctionType(self: *@This(), function_type: FunctionType) TypeId {
        const function_type_id: FunctionTypeId = @intCast(self.function_types.items.len);
        self.function_types.append(self.allocator, function_type) catch unreachable;
        return self.addType(.{ .Function = function_type_id });
    }

    pub fn getArrayType(self: *const @This(), element_type_id: TypeId) ?TypeId {
        return self.array_type_id_by_element_type_id.get(element_type_id);
    }

    pub fn getOrCreateArrayType(self: *@This(), element_type_id: TypeId) TypeId {
        if (self.array_type_id_by_element_type_id.get(element_type_id)) |existing_type_id| {
            return existing_type_id;
        }

        const type_id = self.addType(.{ .Array = element_type_id });
        self.array_type_id_by_element_type_id.put(element_type_id, type_id) catch unreachable;
        return type_id;
    }

    pub fn getType(self: *const @This(), type_id: TypeId) Type {
        return self.types.items[type_id];
    }
};

pub const StructureType = struct {
    symbol_id: symbols.SymbolId,
    name: []const u8,
    fields: []const Field,
    field_index_by_name: std.StringHashMap(u32),
    function_symbol_id_by_name: std.StringHashMap(symbols.SymbolId),
};

pub const Field = struct {
    name: []const u8,
    type_id: TypeId,
};

pub const FunctionType = struct {
    parameter_types: []TypeId,
    return_type: TypeId,
};

pub const StructureConstructionLayout = struct {
    field_indices: []const u32,
};

pub const ArrayInstanceMethod = enum {
    Append,
};

pub const ArrayInstanceField = enum {
    Length,
};

pub const StringInstanceMethod = enum {
    Trim,
    Split,
    ToInt,
};

pub const IntegerInstanceMethod = enum {
    ToString,
};

pub const StringInstanceField = enum {
    Length,
};

pub const MemberAccess = union(enum) {
    StructureInstanceFieldAccess: struct {
        field_index: u32,
    },
    StructureInstanceMethodAccess: struct {
        structure_symbol_id: symbols.SymbolId,
        function_symbol_id: symbols.SymbolId,
    },
    StructureTypeFunctionAccess: struct {
        structure_symbol_id: symbols.SymbolId,
        function_symbol_id: symbols.SymbolId,
    },
    ArrayInstanceMethodAccess: ArrayInstanceMethod,
    ArrayInstanceFieldAccess: ArrayInstanceField,
    IntegerInstanceMethodAccess: IntegerInstanceMethod,
    StringInstanceMethodAccess: StringInstanceMethod,
    StringInstanceFieldAccess: StringInstanceField,
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
        .String => BinaryOperatorRules.init(.{
            .Add = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.string_type_id },
            .Equal = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.boolean_type_id },
            .NotEqual = .{ .argument_type_id = type_store.string_type_id, .return_type_id = type_store.boolean_type_id },
            .LessThan = null,
            .LessThanOrEqual = null,
            .GreaterThan = null,
            .GreaterThanOrEqual = null,
            .Subtract = null,
            .Multiply = null,
            .Divide = null,
            .And = null,
            .Or = null,
        }),
        .Unit,
        .Structure,
        .Function,
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
        .Function,
        .Array,
        .TaggedUnion,
        => null,
    };
}

pub const TypeBySymbolId = std.AutoHashMap(symbols.SymbolId, TypeId);
pub const TypeByNodeId = std.AutoHashMap(ast.NodeId, TypeId);
pub const StructureConstructionLayoutByNodeId = std.AutoHashMap(ast.NodeId, StructureConstructionLayout);
pub const MemberAccessByNodeId = std.AutoHashMap(ast.NodeId, MemberAccess);
