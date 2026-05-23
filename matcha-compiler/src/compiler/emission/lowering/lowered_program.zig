const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const typing = @import("typing");

pub const LoweredProgram = struct {
    analyzed_program: *const semantic_analysis.AnalyzedProgram,
    llvm_ir_type_by_type_id: []const []const u8,
    structure_symbol_id_by_type_id: []const ?symbols.SymbolId,

    pub fn llvmIrType(self: *const @This(), type_id: typing.TypeId) []const u8 {
        return self.llvm_ir_type_by_type_id[@intCast(type_id)];
    }

    pub fn structureSymbolForTypeId(self: *const @This(), type_id: typing.TypeId) symbols.Symbol {
        const symbol_id = self.structure_symbol_id_by_type_id[@intCast(type_id)] orelse unreachable;
        return self.analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id);
    }
};
