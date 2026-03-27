const std = @import("std");
const symbols = @import("symbols");

const ScopeBindings = std.StringHashMap(symbols.SymbolId);

pub const Scope = struct {
    parent: ?*const Scope,
    bindings: ScopeBindings,

    pub fn init(allocator: std.mem.Allocator, parent: ?*const Scope) @This() {
        return .{
            .parent = parent,
            .bindings = ScopeBindings.init(allocator),
        };
    }

    pub fn insertSymbol(self: *@This(), name: []const u8, symbol_id: symbols.SymbolId) !void {
        try self.bindings.put(name, symbol_id);
    }

    pub fn lookupSymbol(self: *const @This(), name: []const u8) ?symbols.SymbolId {
        var current_scope: ?*const Scope = self;
        while (current_scope) |scope| : (current_scope = scope.parent) {
            if (scope.bindings.get(name)) |symbol_id| return symbol_id;
        }

        return null;
    }
};
