const std = @import("std");

const SymbolId = @import("symbol.zig").SymbolId;
const Symbol = @import("symbol.zig").Symbol;
const SymbolKind = @import("symbol.zig").SymbolKind;
const SymbolKindTag = @import("symbol.zig").SymbolKindTag;
const SymbolCreationPayload = @import("symbol.zig").SymbolCreationPayload;
const PreliminarySymbolCreationPayload = @import("symbol.zig").PreliminarySymbolCreationPayload;
const PreliminarySymbol = @import("symbol.zig").PreliminarySymbol;

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

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .preliminary_entries = std.AutoHashMap(SymbolId, PreliminarySymbol).init(arena),
            .entries = std.AutoHashMap(SymbolId, Symbol).init(arena),
            .next_symbol_id = 0,
        };
    }

    pub fn insertSymbol(self: *@This(), payload: SymbolCreationPayload) !SymbolId {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;
        try self.entries.put(symbol_id, .{
            .id = symbol_id,
            .name = payload.name,
            .declared_at = payload.declared_at,
            .kind = payload.kind,
        });

        return symbol_id;
    }

    pub fn insertPreliminarySymbol(self: *@This(), payload: PreliminarySymbolCreationPayload) !SymbolId {
        const symbol_id = self.next_symbol_id;
        self.next_symbol_id += 1;
        try self.preliminary_entries.put(symbol_id, .{
            .id = symbol_id,
            .name = payload.name,
            .declared_at = payload.declared_at,
            .kind = payload.kind,
        });

        return symbol_id;
    }

    pub fn finalizePreliminarySymbol(self: *@This(), symbol_id: SymbolId, kind: SymbolKind) !void {
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
        try self.entries.put(symbol_id, .{
            .id = preliminary.id,
            .name = preliminary.name,
            .declared_at = preliminary.declared_at,
            .kind = kind,
        });
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
