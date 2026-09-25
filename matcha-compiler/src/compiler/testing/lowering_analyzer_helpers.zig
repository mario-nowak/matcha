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
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !LoweringAnalyzerFixture {
    const allocator = arena.allocator();
    const analyzed_program = try setupAnalyzedProgram(arena, source);

    const llvm_type_table_lowerer = try allocator.create(lowering.LlvmTypeTableLowerer);
    llvm_type_table_lowerer.* = lowering.LlvmTypeTableLowerer.init(allocator);
    const structure_symbol_lowerer = try allocator.create(lowering.StructureSymbolLowerer);
    structure_symbol_lowerer.* = lowering.StructureSymbolLowerer.init(allocator);
    const call_lowerer = try allocator.create(lowering.CallLowerer);
    call_lowerer.* = lowering.CallLowerer.init(allocator);
    const member_access_lowerer = try allocator.create(lowering.MemberAccessLowerer);
    member_access_lowerer.* = lowering.MemberAccessLowerer.init(allocator);
    const binary_operation_lowerer = try allocator.create(lowering.BinaryOperationLowerer);
    binary_operation_lowerer.* = lowering.BinaryOperationLowerer.init(allocator);
    const place_lowerer = try allocator.create(lowering.PlaceLowerer);
    place_lowerer.* = lowering.PlaceLowerer.init(allocator);
    const structure_layout_lowerer = try allocator.create(lowering.StructureLayoutLowerer);
    structure_layout_lowerer.* = lowering.StructureLayoutLowerer.init(allocator);
    const function_layout_lowerer = try allocator.create(lowering.FunctionLayoutLowerer);
    function_layout_lowerer.* = lowering.FunctionLayoutLowerer.init(allocator);

    const lowering_analyzer = try allocator.create(LoweringAnalyzer);
    lowering_analyzer.* = LoweringAnalyzer.init(
        llvm_type_table_lowerer,
        structure_symbol_lowerer,
        call_lowerer,
        member_access_lowerer,
        binary_operation_lowerer,
        place_lowerer,
        structure_layout_lowerer,
        function_layout_lowerer,
    );

    return .{
        .analyzed_program = analyzed_program,
        .lowering_analyzer = lowering_analyzer,
    };
}
