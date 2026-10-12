const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");

const TypeStore = @import("type_store.zig").TypeStore;

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

pub const TypeIdBySymbolId = std.AutoHashMap(symbols.SymbolId, TypeId);

pub const TypeIdByNodeId = std.AutoHashMap(ast.NodeId, TypeId);

pub const MemberAccessByNodeId = std.AutoHashMap(ast.NodeId, MemberAccess);

pub const UnionCaseIndexByPatternId = std.AutoHashMap(ast.NodeId, u32);
