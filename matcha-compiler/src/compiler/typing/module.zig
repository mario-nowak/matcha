const std = @import("std");
const symbols = @import("symbols");
const ast = @import("ast");

pub const TypeId = u32;

pub const TypeKind = enum {
    unit,
    boolean,
    integer,
    string,
    structure,
    function,
    array,
    @"union",
    // Internal type
    union_constructor,
};

pub const Type = union(TypeKind) {
    unit,
    boolean,
    integer,
    string,

    structure: StructureType,
    function: FunctionType,
    array: TypeId,
    @"union": UnionType,

    union_constructor: UnionConstructor,

    pub fn name(self: @This(), store: *const TypeStore, symbol_table: *const symbols.SymbolTable, arena: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .unit => arena.dupe(u8, "unit"),
            .boolean => arena.dupe(u8, "boolean"),
            .integer => arena.dupe(u8, "int"),
            .string => arena.dupe(u8, "string"),
            .structure => |structure_type| arena.dupe(u8, symbol_table.getSymbol(structure_type.symbol_id).name),
            .array => |element_type_id| std.fmt.allocPrint(arena, "{s}[]", .{try store.getType(element_type_id).name(store, symbol_table, arena)}),
            .function => |function_type| {
                var parameter_text = std.ArrayList(u8){};
                for (function_type.parameter_type_ids, 0..) |parameter_type_id, index| {
                    if (index > 0) {
                        try parameter_text.appendSlice(arena, ", ");
                    }
                    try parameter_text.appendSlice(arena, try store.getType(parameter_type_id).name(store, symbol_table, arena));
                }
                return std.fmt.allocPrint(
                    arena,
                    "function taking ({s}) and returning {s}",
                    .{ parameter_text.items, try store.getType(function_type.return_type_id).name(store, symbol_table, arena) },
                );
            },
            .@"union" => |union_type| arena.dupe(u8, symbol_table.getSymbol(union_type.symbol_id).name),
            .union_constructor => arena.dupe(u8, "union constructor"),
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
    arena: std.mem.Allocator,
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

    pub fn init(arena: std.mem.Allocator) !@This() {
        var store = @This(){
            .arena = arena,
            .preliminary_entries = std.AutoHashMap(TypeId, PreliminaryType).init(arena),
            .entries = std.AutoHashMap(TypeId, Type).init(arena),
            .next_type_id = 0,
            .array_type_id_by_element_type_id = std.AutoHashMap(TypeId, TypeId).init(arena),
            .unit_type_id = undefined,
            .boolean_type_id = undefined,
            .integer_type_id = undefined,
            .string_type_id = undefined,
        };

        store.unit_type_id = try store.addType(.unit);
        store.boolean_type_id = try store.addType(.boolean);
        store.integer_type_id = try store.addType(.integer);
        store.string_type_id = try store.addType(.string);

        return store;
    }

    pub fn addType(self: *@This(), matcha_type: Type) !TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        try self.entries.put(type_id, matcha_type);

        return type_id;
    }

    pub fn addPreliminaryType(self: *@This(), kind: TypeKind) !TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        try self.preliminary_entries.put(type_id, .{ .kind = kind });

        return type_id;
    }

    pub fn finalizeType(self: *@This(), type_id: TypeId, matcha_type: Type) !void {
        const removed_entry = self.preliminary_entries.fetchRemove(type_id) orelse {
            if (self.entries.contains(type_id)) {
                std.debug.panic("Internal Compiler Error: Type {d} is already finalized", .{type_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid type ID: {d}", .{type_id});
        };
        if (removed_entry.value.kind != std.meta.activeTag(matcha_type)) {
            std.debug.panic("Internal Compiler Error: Cannot change kind of type {d} during finalization", .{type_id});
        }
        try self.entries.put(type_id, matcha_type);
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

    pub fn getOrCreateArrayType(self: *@This(), element_type_id: TypeId) !TypeId {
        if (self.array_type_id_by_element_type_id.get(element_type_id)) |existing_type_id| {
            return existing_type_id;
        }

        const type_id = try self.addType(.{ .array = element_type_id });
        try self.array_type_id_by_element_type_id.put(element_type_id, type_id);
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
};

pub const StructureTypeField = struct {
    name: []const u8,
    type_id: TypeId,
};

pub const UnionType = struct {
    symbol_id: symbols.SymbolId,
    cases: []UnionTypeCase,
};

pub const UnionTypeCase = struct {
    type_id: TypeId,
    constructor_type_id: TypeId,
};

pub const UnionConstructor = struct {
    union_type_id: TypeId,
    case_index: u32,
};

pub const FunctionType = struct {
    parameter_type_ids: []const TypeId,
    return_type_id: TypeId,
};

pub const ArrayInstanceMethod = enum {
    append,
};

pub const ArrayInstanceField = enum {
    length,
};

pub const StringInstanceMethod = enum {
    trim,
    split,
    to_int,
    slice,
};

pub const IntegerInstanceMethod = enum {
    to_string,
};

pub const StringInstanceField = enum {
    length,
};

pub const MemberAccess = union(enum) {
    structure_instance_field_access: struct {
        field_index: u32,
    },
    union_type_base_case_access: struct {
        case_index: u32,
    },
    instance_method_access: struct {
        owner_symbol_id: symbols.SymbolId,
        function_symbol_id: symbols.SymbolId,
    },
    type_function_access: struct {
        owner_symbol_id: symbols.SymbolId,
        function_symbol_id: symbols.SymbolId,
    },
    string_instance_field_access: StringInstanceField,
    array_instance_field_access: ArrayInstanceField,
    array_instance_method_access: ArrayInstanceMethod,
    integer_instance_method_access: IntegerInstanceMethod,
    string_instance_method_access: StringInstanceMethod,
};

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

pub const TypeIdBySymbolId = std.AutoHashMap(symbols.SymbolId, TypeId);
pub const TypeIdByNodeId = std.AutoHashMap(ast.NodeId, TypeId);
pub const MemberAccessByNodeId = std.AutoHashMap(ast.NodeId, MemberAccess);
pub const UnionCaseIndexByPatternId = std.AutoHashMap(ast.NodeId, u32);
