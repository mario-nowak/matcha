const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const typing = @import("typing");
const llvm_type = @import("llvm_type.zig");
const lowered_program = @import("lowered_program.zig");

pub const LoweringAnalyzer = struct {
    allocator: std.mem.Allocator,
    llvm_ir_type_by_type_id: std.ArrayList([]const u8),
    structure_symbol_id_by_type_id: std.ArrayList(?symbols.SymbolId),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .llvm_ir_type_by_type_id = .{},
            .structure_symbol_id_by_type_id = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_ir_type_by_type_id.deinit(self.allocator);
        self.structure_symbol_id_by_type_id.deinit(self.allocator);
    }

    pub fn analyzeProgram(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowered_program.LoweredProgram {
        self.llvm_ir_type_by_type_id.clearRetainingCapacity();
        self.structure_symbol_id_by_type_id.clearRetainingCapacity();

        for (0..analyzed_program.type_store.types.items.len) |index| {
            const type_id: typing.TypeId = @intCast(index);
            self.llvm_ir_type_by_type_id.append(
                self.allocator,
                llvm_type.llvmIrType(&analyzed_program.type_store, type_id),
            ) catch unreachable;
            self.structure_symbol_id_by_type_id.append(self.allocator, null) catch unreachable;
        }

        var type_by_symbol_iterator = analyzed_program.type_by_symbol_id.iterator();
        while (type_by_symbol_iterator.next()) |entry| {
            const symbol_id = entry.key_ptr.*;
            const type_id = entry.value_ptr.*;
            const symbol = analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id);
            switch (symbol.kind) {
                .Structure => self.structure_symbol_id_by_type_id.items[@intCast(type_id)] = symbol_id,
                else => {},
            }
        }

        return .{
            .analyzed_program = analyzed_program,
            .llvm_ir_type_by_type_id = self.llvm_ir_type_by_type_id.items,
            .structure_symbol_id_by_type_id = self.structure_symbol_id_by_type_id.items,
        };
    }
};
