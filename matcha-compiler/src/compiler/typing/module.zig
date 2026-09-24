const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const TypeId = u32;

pub const TypeKind = enum {
    Unit,
    Boolean,
    Integer,
    String,
    Structure,
    Function,
    Array,
    TaggedUnion,
};

pub const Type = union(TypeKind) {
    Unit,
    Boolean,
    Integer,
    String,

    Structure: StructureType,
    Function: FunctionType,
    Array: TypeId,
    TaggedUnion,

    pub fn name(self: @This(), store: *const TypeStore, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .Unit => allocator.dupe(u8, "unit"),
            .Boolean => allocator.dupe(u8, "boolean"),
            .Integer => allocator.dupe(u8, "int"),
            .String => allocator.dupe(u8, "string"),
            .Structure => |structure_type| allocator.dupe(u8, structure_type.name),
            .Array => |element_type_id| std.fmt.allocPrint(allocator, "{s}[]", .{try store.getType(element_type_id).name(store, allocator)}),
            .Function => |function_type| {
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

/// A type whose identity is allocated but whose payload is not yet known.
/// Only type seeding creates these, so that mutually recursive types can reference each other.
/// All preliminary types must be finalized before type analysis reads them.
pub const PreliminaryType = struct {
    kind: TypeKind,
};

/// Table for storing types by their ID.
pub const TypeStore = struct {
    allocator: std.mem.Allocator,
    preliminary_entries: std.AutoHashMap(TypeId, PreliminaryType),
    entries: std.AutoHashMap(TypeId, Type),
    next_type_id: TypeId,
    array_type_id_by_element_type_id: std.AutoHashMap(TypeId, TypeId),
    unit_type_id: TypeId,
    boolean_type_id: TypeId,
    integer_type_id: TypeId,
    string_type_id: TypeId,

    pub const Iterator = struct {
        inner: std.AutoHashMap(TypeId, Type).Iterator,

        pub const Entry = struct {
            type_id: TypeId,
            matcha_type: Type,
        };

        pub fn next(self: *@This()) ?Entry {
            const entry = self.inner.next() orelse return null;
            return .{ .type_id = entry.key_ptr.*, .matcha_type = entry.value_ptr.* };
        }
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        var store = @This(){
            .allocator = allocator,
            .preliminary_entries = std.AutoHashMap(TypeId, PreliminaryType).init(allocator),
            .entries = std.AutoHashMap(TypeId, Type).init(allocator),
            .next_type_id = 0,
            .array_type_id_by_element_type_id = std.AutoHashMap(TypeId, TypeId).init(allocator),
            .unit_type_id = undefined,
            .boolean_type_id = undefined,
            .integer_type_id = undefined,
            .string_type_id = undefined,
        };

        store.unit_type_id = store.addType(.Unit);
        store.boolean_type_id = store.addType(.Boolean);
        store.integer_type_id = store.addType(.Integer);
        store.string_type_id = store.addType(.String);

        return store;
    }

    pub fn addType(self: *@This(), matcha_type: Type) TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        self.entries.put(type_id, matcha_type) catch unreachable;

        return type_id;
    }

    pub fn addPreliminaryType(self: *@This(), kind: TypeKind) TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        self.preliminary_entries.put(type_id, .{ .kind = kind }) catch unreachable;

        return type_id;
    }

    pub fn finalizeType(self: *@This(), type_id: TypeId, matcha_type: Type) void {
        const removed_entry = self.preliminary_entries.fetchRemove(type_id) orelse {
            if (self.entries.contains(type_id)) {
                std.debug.panic("Internal Compiler Error: Type {d} is already finalized", .{type_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid type ID: {d}", .{type_id});
        };
        if (removed_entry.value.kind != std.meta.activeTag(matcha_type)) {
            std.debug.panic("Internal Compiler Error: Cannot change kind of type {d} during finalization", .{type_id});
        }
        self.entries.put(type_id, matcha_type) catch unreachable;
    }

    pub fn getType(self: *const @This(), type_id: TypeId) Type {
        return self.entries.get(type_id) orelse {
            if (self.preliminary_entries.contains(type_id)) {
                std.debug.panic("Internal Compiler Error: Type {d} is not finalized", .{type_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid type ID: {d}", .{type_id});
        };
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

    /// Number of allocated type IDs. IDs are dense, so all IDs are smaller than this count.
    pub fn count(self: *const @This()) u32 {
        return self.next_type_id;
    }

    pub fn assertAllFinalized(self: *const @This()) void {
        if (self.preliminary_entries.count() == 0) return;
        var preliminary_types = self.preliminary_entries.iterator();
        while (preliminary_types.next()) |entry| {
            std.debug.print("Type {d} ({s}) is not finalized\n", .{ entry.key_ptr.*, @tagName(entry.value_ptr.kind) });
        }

        std.debug.panic("Internal Compiler Error: {d} types are not finalized", .{self.preliminary_entries.count()});
    }

    pub fn iterator(self: *const @This()) Iterator {
        return .{ .inner = self.entries.iterator() };
    }
};

pub const StructureType = struct {
    symbol_id: symbols.SymbolId,
    name: []const u8,
    fields: []const StructureTypeField,
    function_symbol_ids: []const symbols.SymbolId,

    pub fn getFieldIndex(self: @This(), field_name: []const u8) ?u32 {
        for (self.fields, 0..) |field, index| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return @intCast(index);
            }
        }
        return null;
    }

    pub fn getFunctionSymbolId(
        self: @This(),
        symbol_table: *const symbols.SymbolTable,
        member_name: []const u8,
    ) ?symbols.SymbolId {
        for (self.function_symbol_ids) |function_symbol_id| {
            if (std.mem.eql(u8, symbol_table.getSymbol(function_symbol_id).name, member_name)) {
                return function_symbol_id;
            }
        }
        return null;
    }
};

pub const StructureTypeField = struct {
    name: []const u8,
    type_id: TypeId,
};

pub const FunctionType = struct {
    parameter_types: []const TypeId,
    return_type: TypeId,
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
        .Structure => BinaryOperatorRules.init(.{
            .Add = null,
            .Equal = .{ .argument_type_id = operand_type_id, .return_type_id = type_store.boolean_type_id },
            .NotEqual = .{ .argument_type_id = operand_type_id, .return_type_id = type_store.boolean_type_id },
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

pub const TypeIdBySymbolId = std.AutoHashMap(symbols.SymbolId, TypeId);
pub const TypeIdByNodeId = std.AutoHashMap(ast.NodeId, TypeId);
pub const MemberAccessByNodeId = std.AutoHashMap(ast.NodeId, MemberAccess);
