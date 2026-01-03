const std = @import("std");
const lexer = @import("../lexer.zig");
const Token = lexer.Token;

pub const Symbol = struct {
    declaredAt: Token,
};

const SymbolTable = std.StringHashMap(Symbol);

pub const Scope = struct {
    parent: ?*const Scope,
    symbols: SymbolTable,

    pub fn init(allocator: std.mem.Allocator, parent: ?*const Scope) @This() {
        return .{
            .parent = parent,
            .symbols = SymbolTable.init(allocator),
        };
    }

    pub fn insertSymbol(self: *@This(), name: []const u8, symbol: *const Symbol) !void {
        try self.symbols.put(name, symbol.*);
    }

    pub fn lookupSymbol(self: *const @This(), name: []const u8) ?Symbol {
        var current_scope: ?*const Scope = self;
        while (current_scope) |scope| : (current_scope = scope.parent) {
            if (scope.symbols.get(name)) |symbol| return symbol;
        }

        return null;
    }
};
