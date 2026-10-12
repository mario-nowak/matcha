const std = @import("std");
const ast = @import("ast");

const SymbolId = @import("symbol.zig").SymbolId;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub const SymbolIdByNodeId = std.AutoHashMap(ast.NodeId, SymbolId);

pub const ResolvedProgram = struct {
    program: ast.Program,
    symbol_table: SymbolTable,
    symbol_id_by_node_id: SymbolIdByNodeId,
};
