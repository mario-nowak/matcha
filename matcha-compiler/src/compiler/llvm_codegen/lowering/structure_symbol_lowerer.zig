const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const typing = @import("typing");

pub const StructureSymbolLowerer = struct {
    allocator: std.mem.Allocator,
    structure_symbol_id_by_type_id: std.ArrayList(?symbols.SymbolId),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .structure_symbol_id_by_type_id = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.structure_symbol_id_by_type_id.deinit(self.allocator);
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) []const ?symbols.SymbolId {
        self.structure_symbol_id_by_type_id.clearRetainingCapacity();

        for (0..analyzed_program.type_store.types.items.len) |_| {
            self.structure_symbol_id_by_type_id.append(self.allocator, null) catch unreachable;
        }

        var type_by_symbol_iterator = analyzed_program.type_by_symbol_id.iterator();
        while (type_by_symbol_iterator.next()) |entry| {
            const symbol_id = entry.key_ptr.*;
            const type_id: typing.TypeId = entry.value_ptr.*;
            const symbol = analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id);
            switch (symbol.kind) {
                .Structure => self.structure_symbol_id_by_type_id.items[@intCast(type_id)] = symbol_id,
                else => {},
            }
        }

        return self.structure_symbol_id_by_type_id.items;
    }
};
