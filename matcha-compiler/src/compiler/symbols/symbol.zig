const std = @import("std");
const lexing = @import("lexing");

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
    binding: BindingSymbolInformation,
    function: FunctionSymbolInformation,
    structure: StructureSymbolInformation,
    @"union": UnionSymbolInformation,
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
    user_defined,
    builtin_print_int,
    builtin_print_string,
    builtin_read_file,
    builtin_read_file_chunk,
    builtin_read_line,
    builtin_get_arguments,
    builtin_start_process,
};

pub const BindingMutability = enum {
    mutable,
    immutable,
};

pub const ResolvedTypeReference = union(enum) {
    builtin: BuiltinType,
    symbol: SymbolId,
    array: *ResolvedTypeReference,
};

pub const BuiltinType = enum {
    unit,
    boolean,
    integer,
    string,
};
