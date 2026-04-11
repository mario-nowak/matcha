const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");

pub const SymbolId = u32;

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
    Function: FunctionInfo,
};

pub const FunctionInfo = struct {
    implementation: Implementation,
};

pub const Implementation = union(enum) {
    UserDefined,
    BuiltinPrintInt,
};

pub const BindingMutability = enum {
    Mutable,
    Immutable,
};

pub const SymbolPayload = struct {
    name: []const u8,
    declared_at: ?lexing.Token,
    kind: SymbolKind,
};

pub const SymbolTable = struct {
    entries: std.AutoHashMap(SymbolId, Symbol),
    next_symbol_id: SymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .entries = std.AutoHashMap(SymbolId, Symbol).init(allocator),
            .next_symbol_id = 0,
        };
    }

    pub fn insertSymbol(self: *@This(), payload: SymbolPayload) Symbol {
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

pub const SymbolIdByNodeId = std.AutoHashMap(ast.NodeId, SymbolId);
pub const ParameterSymbolIdsByFunctionSymbolId = std.AutoHashMap(SymbolId, []const SymbolId);

pub const ResolvedProgram = struct {
    program: ast.Program,
    symbol_table: SymbolTable,
    symbol_id_by_node_id: SymbolIdByNodeId,
    parameter_symbol_ids_by_function_symbol_id: ParameterSymbolIdsByFunctionSymbolId,
};
