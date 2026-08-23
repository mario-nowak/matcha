const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");

pub const LoweredProgram = struct {
    analyzed_program: *const semantic_analysis.AnalyzedProgram,
    llvm_ir_type_by_type_id: []const []const u8,
    structure_symbol_id_by_type_id: []const ?symbols.SymbolId,
    call_dispatch_decision_by_node_id: lowering_types.CallDispatchDecisionByNodeId,
    member_access_decision_by_node_id: lowering_types.MemberAccessDecisionByNodeId,
    binary_operation_decision_by_node_id: lowering_types.BinaryOperationDecisionByNodeId,
    place_decision_by_node_id: lowering_types.PlaceDecisionByNodeId,
    runtime_requirements_plan: lowering_types.RuntimeRequirementsPlan,
    structure_layout_kind_by_type_id: lowering_types.StructureLayoutKindByTypeId,
    function_layout_by_symbol_id: lowering_types.FunctionLayoutBySymbolId,

    pub fn getLlvmIrType(self: *const @This(), type_id: typing.TypeId) []const u8 {
        return self.llvm_ir_type_by_type_id[@intCast(type_id)];
    }

    pub fn getStructureSymbolForTypeId(self: *const @This(), type_id: typing.TypeId) symbols.Symbol {
        const symbol_id = self.structure_symbol_id_by_type_id[@intCast(type_id)] orelse unreachable;
        return self.analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id);
    }
};
