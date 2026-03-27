const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");

pub const SymbolId = u32;

pub const Symbol = struct {
    id: SymbolId,
    name: []const u8,
    declaredAt: lexing.Token,
};

pub const SymbolTable = std.AutoHashMap(SymbolId, Symbol);
pub const NameResolutionMap = std.AutoHashMap(ast.NodeId, SymbolId);

pub const ResolvedProgram = struct {
    program: *const ast.Program,
    symbol_table: SymbolTable,
    name_resolution_map: NameResolutionMap,
};
