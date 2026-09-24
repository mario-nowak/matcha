const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");

pub const SymbolId = u32;

/// A symbol identifies a named entity in the program, such as a value binding, function, or type.
/// The program or compiler can introduce the entity.
/// References to the same entity resolve to the same symbol.
/// Different entities can have the same name but different symbols.
/// Example:
/// ```matcha
/// item User = structure {
///     name: string;
///     age: int;
/// };
/// val mario: User = .{ name = "Mario", age = 27 }; // The name `User` here and in the definition above resolve to the same symbol
/// {
///     var name = mario.name; // The name `mario` here and in the declaration above resolves to the same symbol
///     val luigi: User = .{ name = "Luigi", age = 26 };
/// }
/// {
///     val luigi: User = .{ name = "Luigi", age = 26 }; // The name `luigi` here and in the block before don't resolve to the same symbol
/// }
/// ```
pub const Symbol = struct {
    id: SymbolId,
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKind,
};

pub const SymbolKind = union(enum) {
    Binding: BindingSymbolInformation,
    Function: FunctionSymbolInformation,
    Structure: StructureSymbolInformation,
    Union: UnionSymbolInformation,
};

pub const SymbolKindTag = std.meta.Tag(SymbolKind);

pub const SymbolCreationPayload = struct {
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKind,
};

pub const PreliminarySymbolCreationPayload = struct {
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKindTag,
};

pub const PreliminarySymbol = struct {
    id: SymbolId,
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKindTag,
};

pub const BindingSymbolInformation = struct {
    binding_mutability: BindingMutability,
    declared_type_reference: ?ResolvedTypeReference = null,
};

pub const FunctionSymbolInformation = struct {
    parameter_symbol_ids: []const SymbolId,
    return_type_reference: ResolvedTypeReference,
    implementation_kind: FunctionImplementationKind,
};

pub const StructureSymbolInformation = struct {
    fields: []const ResolvedStructureField,
    function_symbol_ids: []const SymbolId,
};

pub const ResolvedStructureField = struct {
    name: []const u8,
    type_reference: ResolvedTypeReference,
};

pub const UnionSymbolInformation = struct {
    cases: []const ResolvedUnionCase,
    function_symbol_ids: []const SymbolId,
};

pub const ResolvedUnionCase = struct {
    name: []const u8,
    type_reference: ResolvedTypeReference,
};

pub const FunctionImplementationKind = union(enum) {
    UserDefined,
    BuiltinPrintInt,
    BuiltinPrintString,
    BuiltinReadFile,
    BuiltinReadLine,
    BuiltinGetArguments,
};

pub const BindingMutability = enum {
    Mutable,
    Immutable,
};

/// Table for storing symbols by their ID.
pub const SymbolTable = struct {
    preliminary_entries: std.AutoHashMap(SymbolId, PreliminarySymbol),
    entries: std.AutoHashMap(SymbolId, Symbol),
    next_symbol_id: SymbolId,

    pub const Iterator = struct {
        inner: std.AutoHashMap(SymbolId, Symbol).ValueIterator,

        pub fn next(self: *@This()) ?Symbol {
            const symbol = self.inner.next() orelse return null;
            return symbol.*;
        }
    };

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .preliminary_entries = std.AutoHashMap(SymbolId, PreliminarySymbol).init(allocator),
            .entries = std.AutoHashMap(SymbolId, Symbol).init(allocator),
            .next_symbol_id = 0,
        };
    }

    pub fn insertSymbol(self: *@This(), payload: SymbolCreationPayload) SymbolId {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;
        self.entries.put(symbol_id, .{
            .id = symbol_id,
            .name = payload.name,
            .declared_at = payload.declared_at,
            .kind = payload.kind,
        }) catch unreachable;

        return symbol_id;
    }

    pub fn insertPreliminarySymbol(self: *@This(), payload: PreliminarySymbolCreationPayload) SymbolId {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;
        self.preliminary_entries.put(symbol_id, .{
            .id = symbol_id,
            .name = payload.name,
            .declared_at = payload.declared_at,
            .kind = payload.kind,
        }) catch unreachable;

        return symbol_id;
    }

    pub fn finalizePreliminarySymbol(self: *@This(), symbol_id: SymbolId, kind: SymbolKind) void {
        const removed_entry = self.preliminary_entries.fetchRemove(symbol_id) orelse {
            if (self.entries.contains(symbol_id)) {
                std.debug.panic("Internal Compiler Error: Symbol {d} is already finalized", .{symbol_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid symbol ID: {d}", .{symbol_id});
        };
        const preliminary = removed_entry.value;
        if (preliminary.kind != std.meta.activeTag(kind)) {
            std.debug.panic("Internal Compiler Error: Cannot change kind of symbol {d} during finalization", .{symbol_id});
        }
        self.entries.put(symbol_id, .{
            .id = preliminary.id,
            .name = preliminary.name,
            .declared_at = preliminary.declared_at,
            .kind = kind,
        }) catch unreachable;
    }

    pub fn getSymbol(self: *const @This(), symbol_id: SymbolId) Symbol {
        return self.entries.get(symbol_id) orelse {
            if (self.preliminary_entries.contains(symbol_id)) {
                std.debug.panic("Internal Compiler Error: Symbol {d} is not finalized", .{symbol_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid symbol ID: {d}", .{symbol_id});
        };
    }

    pub fn getSymbolKind(self: *const @This(), symbol_id: SymbolId) SymbolKindTag {
        if (self.entries.get(symbol_id)) |symbol| {
            return std.meta.activeTag(symbol.kind);
        }
        const preliminary = self.preliminary_entries.get(symbol_id) orelse
            std.debug.panic("Internal Compiler Error: Invalid symbol ID: {d}", .{symbol_id});

        return preliminary.kind;
    }

    pub fn assertAllFinalized(self: *const @This()) void {
        if (self.preliminary_entries.count() == 0) return;
        var preliminary_symbols = self.preliminary_entries.valueIterator();
        while (preliminary_symbols.next()) |symbol| {
            std.debug.print("Symbol {d} ('{s}') is not finalized\n", .{ symbol.id, symbol.name });
        }

        std.debug.panic("Internal Compiler Error: {d} symbols are not finalized", .{self.preliminary_entries.count()});
    }

    pub fn iterator(self: *const @This()) Iterator {
        return .{ .inner = self.entries.valueIterator() };
    }
};

pub const ResolvedTypeReference = union(enum) {
    Builtin: BuiltinType,
    Symbol: SymbolId,
    Array: *ResolvedTypeReference,
};

pub const BuiltinType = enum {
    Unit,
    Boolean,
    Integer,
    String,
};

pub const SymbolIdByNodeId = std.AutoHashMap(ast.NodeId, SymbolId);

pub const ResolvedProgram = struct {
    program: ast.Program,
    symbol_table: SymbolTable,
    symbol_id_by_node_id: SymbolIdByNodeId,
};
