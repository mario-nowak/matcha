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
    Binding: struct {
        binding_mutability: BindingMutability,
    },
    Function: FunctionSymbolInformation,
    Structure,
    Union,
};

pub const FunctionSymbolInformation = struct {
    implementation_kind: FunctionImplementationKind,
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
    entries: std.AutoHashMap(SymbolId, Symbol),
    next_symbol_id: SymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .entries = std.AutoHashMap(SymbolId, Symbol).init(allocator),
            .next_symbol_id = 0,
        };
    }

    pub fn insertSymbol(self: *@This(), payload: SymbolCreationPayload) Symbol {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;

        const symbol = Symbol{
            .id = symbol_id,
            .name = payload.name,
            .declared_at = payload.declared_at,
            .kind = payload.kind,
        };
        self.entries.put(symbol_id, symbol) catch unreachable;

        return symbol;
    }

    pub fn getSymbol(self: *const @This(), symbol_id: SymbolId) Symbol {
        return self.entries.get(symbol_id) orelse {
            std.debug.print("Internal Compiler Error: Invalid symbol ID: {d}\n", .{symbol_id});
            unreachable;
        };
    }
};

pub const SymbolCreationPayload = struct {
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKind,
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

pub const ResolvedParameter = struct {
    symbol_id: SymbolId,
    name: []const u8,
    type_reference: ResolvedTypeReference,
};

pub const ResolvedFunction = struct {
    symbol_id: SymbolId,
    name: []const u8,
    parameters: []ResolvedParameter,
    return_type_reference: ResolvedTypeReference,
    implementation: union(enum) {
        user_defined: struct {
            node_id: ast.NodeId,
            body_node_id: ast.NodeId,
        },
        builtin,
    },
};

pub const ResolvedStructureField = struct {
    name: []const u8,
    type_reference: ResolvedTypeReference,
};

pub const ResolvedStructure = struct {
    symbol_id: SymbolId,
    name: []const u8,
    fields: []ResolvedStructureField,
    function_symbol_ids: []SymbolId,
};

pub const ResolvedUnionCase = struct {
    name: []const u8,
    type_reference: ResolvedTypeReference,
};

pub const ResolvedUnion = struct {
    symbol_id: SymbolId,
    name: []const u8,
    cases: []ResolvedUnionCase,
    function_symbol_ids: []SymbolId,
};

pub const SymbolIdByNodeId = std.AutoHashMap(ast.NodeId, SymbolId);

pub const ResolvedFunctionBySymbolId = std.AutoHashMap(SymbolId, ResolvedFunction);
pub const ResolvedStructureBySymbolId = std.AutoHashMap(SymbolId, ResolvedStructure);
pub const ResolvedUnionBySymbolId = std.AutoHashMap(SymbolId, ResolvedUnion);
pub const AnnotatedTypeReferenceBySymbolId = std.AutoHashMap(SymbolId, ResolvedTypeReference);

pub const ResolvedProgram = struct {
    program: ast.Program,
    symbol_table: SymbolTable,
    symbol_id_by_node_id: SymbolIdByNodeId,
    resolved_function_by_symbol_id: ResolvedFunctionBySymbolId,
    resolved_structure_by_symbol_id: ResolvedStructureBySymbolId,
    resolved_union_by_symbol_id: ResolvedUnionBySymbolId,
    annotated_type_reference_by_symbol_id: AnnotatedTypeReferenceBySymbolId,
};
