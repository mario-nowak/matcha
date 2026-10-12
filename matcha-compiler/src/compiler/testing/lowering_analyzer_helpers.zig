const std = @import("std");
const sources = @import("sources");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");
const lowering = llvm_codegen.lowering;

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const LoweringAnalyzer = lowering.LoweringAnalyzer;
const setupAnalyzedProgramFixture = @import("analyzed_program_helpers.zig").setupAnalyzedProgramFixture;

const LoweringAnalyzerFixture = struct {
    analyzed_program: *const AnalyzedProgram,
    lowering_analyzer: *LoweringAnalyzer,
    source_registry: *const sources.SourceRegistry,
};

pub fn setupLoweringAnalyzerFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !LoweringAnalyzerFixture {
    const arena = arena_state.allocator();
    const analyzed_program_fixture = try setupAnalyzedProgramFixture(arena_state, &.{.{ .path = "main.mt", .source = source }});
    const module_name_lowerer = try arena.create(lowering.ModuleNameLowerer);
    module_name_lowerer.* = lowering.ModuleNameLowerer.init(arena, analyzed_program_fixture.source_registry);

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
    structure_layout_lowerer.* = lowering.StructureLayoutLowerer.init(arena, module_name_lowerer);
    const union_layout_lowerer = try arena.create(lowering.UnionLayoutLowerer);
    union_layout_lowerer.* = lowering.UnionLayoutLowerer.init(arena, module_name_lowerer);
    const function_layout_lowerer = try arena.create(lowering.FunctionLayoutLowerer);
    function_layout_lowerer.* = lowering.FunctionLayoutLowerer.init(arena, module_name_lowerer);

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
        .analyzed_program = analyzed_program_fixture.analyzed_program,
        .lowering_analyzer = lowering_analyzer,
        .source_registry = analyzed_program_fixture.source_registry,
    };
}
