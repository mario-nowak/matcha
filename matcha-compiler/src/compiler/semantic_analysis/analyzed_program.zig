const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("./control_flow/module.zig");
const type_checking = @import("./type_checking/module.zig");
const runtime_representation = @import("./runtime_representation/module.zig");

pub const AnalyzedProgram = struct {
    resolved_program: symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    type_store: typing.TypeStore,
    type_by_symbol_id: typing.TypeBySymbolId,
    type_by_node_id: typing.TypeByNodeId,
    structure_construction_layout_by_node_id: typing.StructureConstructionLayoutByNodeId,
    member_access_by_node_id: typing.MemberAccessByNodeId,
    runtime_representation_result: runtime_representation.RuntimeRepresentationResult,

    pub fn init(
        resolved_program: symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        type_check_result: type_checking.TypeCheckResult,
        runtime_representation_result: runtime_representation.RuntimeRepresentationResult,
    ) @This() {
        return .{
            .resolved_program = resolved_program,
            .exit_behavior_by_node_id = exit_behavior_by_node_id,
            .type_store = type_check_result.type_store,
            .type_by_symbol_id = type_check_result.type_by_symbol_id,
            .type_by_node_id = type_check_result.type_by_node_id,
            .structure_construction_layout_by_node_id = type_check_result.structure_construction_layout_by_node_id,
            .member_access_by_node_id = type_check_result.member_access_by_node_id,
            .runtime_representation_result = runtime_representation_result,
        };
    }
};
