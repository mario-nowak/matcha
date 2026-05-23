const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const lowered_program = @import("lowered_program.zig");

const LlvmTypeTableLowerer = @import("llvm_type_table_lowerer.zig").LlvmTypeTableLowerer;
const StructureSymbolLowerer = @import("structure_symbol_lowerer.zig").StructureSymbolLowerer;
const CallLowerer = @import("call_lowerer.zig").CallLowerer;
const MemberAccessLowerer = @import("member_access_lowerer.zig").MemberAccessLowerer;
const BinaryOperationLowerer = @import("binary_operation_lowerer.zig").BinaryOperationLowerer;
const PlaceLowerer = @import("place_lowerer.zig").PlaceLowerer;
const NodeValueKindLowerer = @import("node_value_kind_lowerer.zig").NodeValueKindLowerer;
const RuntimeRequirementsLowerer = @import("runtime_requirements_lowerer.zig").RuntimeRequirementsLowerer;

pub const LoweringAnalyzer = struct {
    llvm_type_table_lowerer: LlvmTypeTableLowerer,
    structure_symbol_lowerer: StructureSymbolLowerer,
    call_lowerer: CallLowerer,
    member_access_lowerer: MemberAccessLowerer,
    binary_operation_lowerer: BinaryOperationLowerer,
    place_lowerer: PlaceLowerer,
    node_value_kind_lowerer: NodeValueKindLowerer,
    runtime_requirements_lowerer: RuntimeRequirementsLowerer,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .llvm_type_table_lowerer = LlvmTypeTableLowerer.init(allocator),
            .structure_symbol_lowerer = StructureSymbolLowerer.init(allocator),
            .call_lowerer = CallLowerer.init(allocator),
            .member_access_lowerer = MemberAccessLowerer.init(allocator),
            .binary_operation_lowerer = BinaryOperationLowerer.init(allocator),
            .place_lowerer = PlaceLowerer.init(allocator),
            .node_value_kind_lowerer = NodeValueKindLowerer.init(allocator),
            .runtime_requirements_lowerer = RuntimeRequirementsLowerer.init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_type_table_lowerer.deinit();
        self.structure_symbol_lowerer.deinit();
        self.call_lowerer.deinit();
        self.member_access_lowerer.deinit();
        self.binary_operation_lowerer.deinit();
        self.place_lowerer.deinit();
        self.node_value_kind_lowerer.deinit();
    }

    pub fn analyzeProgram(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowered_program.LoweredProgram {
        const llvm_ir_type_by_type_id = self.llvm_type_table_lowerer.lower(analyzed_program);
        const structure_symbol_id_by_type_id = self.structure_symbol_lowerer.lower(analyzed_program);
        const call_dispatch_decision_by_node_id = self.call_lowerer.lower(analyzed_program);
        const member_access_decision_by_node_id = self.member_access_lowerer.lower(analyzed_program);
        const binary_operation_decision_by_node_id = self.binary_operation_lowerer.lower(analyzed_program);
        const place_decision_by_node_id = self.place_lowerer.lower(analyzed_program);
        const node_value_kind_by_node_id = self.node_value_kind_lowerer.lower(analyzed_program);
        const runtime_requirements_plan = self.runtime_requirements_lowerer.lower(analyzed_program);

        return .{
            .analyzed_program = analyzed_program,
            .llvm_ir_type_by_type_id = llvm_ir_type_by_type_id,
            .structure_symbol_id_by_type_id = structure_symbol_id_by_type_id,
            .call_dispatch_decision_by_node_id = call_dispatch_decision_by_node_id,
            .member_access_decision_by_node_id = member_access_decision_by_node_id,
            .binary_operation_decision_by_node_id = binary_operation_decision_by_node_id,
            .place_decision_by_node_id = place_decision_by_node_id,
            .node_value_kind_by_node_id = node_value_kind_by_node_id,
            .runtime_requirements_plan = runtime_requirements_plan,
        };
    }
};
