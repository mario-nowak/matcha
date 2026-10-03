const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");

pub const LoweredProgram = struct {
    analyzed_program: *const semantic_analysis.AnalyzedProgram,
    llvm_ir_type_by_type_id: []const []const u8,
    call_dispatch_decision_by_node_id: lowering_types.CallDispatchDecisionByNodeId,
    member_access_decision_by_node_id: lowering_types.MemberAccessDecisionByNodeId,
    binary_operation_decision_by_node_id: lowering_types.BinaryOperationDecisionByNodeId,
    place_decision_by_node_id: lowering_types.PlaceDecisionByNodeId,
    structure_layout_kind_by_type_id: lowering_types.StructureLayoutKindByTypeId,
    union_layout_by_type_id: lowering_types.UnionLayoutByTypeId,
    function_layout_by_symbol_id: lowering_types.FunctionLayoutBySymbolId,

    pub fn getLlvmIrType(self: *const @This(), type_id: typing.TypeId) []const u8 {
        return self.llvm_ir_type_by_type_id[@intCast(type_id)];
    }
};
