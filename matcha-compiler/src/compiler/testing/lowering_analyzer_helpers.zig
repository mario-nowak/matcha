const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");
const lowering = llvm_codegen.lowering;

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const LoweringAnalyzer = lowering.LoweringAnalyzer;
const setupAnalyzedProgram = @import("analyzed_program_helpers.zig").setupAnalyzedProgram;

const LoweringAnalyzerFixture = struct {
    analyzed_program: *const AnalyzedProgram,
    lowering_analyzer: *LoweringAnalyzer,
};

pub fn setupLoweringAnalyzerFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !LoweringAnalyzerFixture {
    const arena = arena_state.allocator();
    const analyzed_program = try setupAnalyzedProgram(arena_state, source);

    const llvm_type_table_lowerer = try arena.create(lowering.LlvmTypeTableLowerer);
    llvm_type_table_lowerer.* = lowering.LlvmTypeTableLowerer.init(arena);
    const call_lowerer = try arena.create(lowering.CallLowerer);
    call_lowerer.* = lowering.CallLowerer.init(arena);
    const member_access_lowerer = try arena.create(lowering.MemberAccessLowerer);
    member_access_lowerer.* = lowering.MemberAccessLowerer.init(arena);
    const binary_operation_lowerer = try arena.create(lowering.BinaryOperationLowerer);
    binary_operation_lowerer.* = lowering.BinaryOperationLowerer.init(arena);
    const place_lowerer = try arena.create(lowering.PlaceLowerer);
    place_lowerer.* = lowering.PlaceLowerer.init(arena);
    const structure_layout_lowerer = try arena.create(lowering.StructureLayoutLowerer);
    structure_layout_lowerer.* = lowering.StructureLayoutLowerer.init(arena);
    const union_layout_lowerer = try arena.create(lowering.UnionLayoutLowerer);
    union_layout_lowerer.* = lowering.UnionLayoutLowerer.init(arena);
    const function_layout_lowerer = try arena.create(lowering.FunctionLayoutLowerer);
    function_layout_lowerer.* = lowering.FunctionLayoutLowerer.init(arena);

    const lowering_analyzer = try arena.create(LoweringAnalyzer);
    lowering_analyzer.* = LoweringAnalyzer.init(
        llvm_type_table_lowerer,
        call_lowerer,
        member_access_lowerer,
        binary_operation_lowerer,
        place_lowerer,
        structure_layout_lowerer,
        union_layout_lowerer,
        function_layout_lowerer,
    );

    return .{
        .analyzed_program = analyzed_program,
        .lowering_analyzer = lowering_analyzer,
    };
}
