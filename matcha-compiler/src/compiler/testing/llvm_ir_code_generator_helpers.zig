const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");

const AnalyzedProgram = semantic_analysis.AnalyzedProgram;
const LlvmIrCodeGenerator = llvm_codegen.LlvmIrCodeGenerator;
const setupLoweringAnalyzerFixture = @import("lowering_analyzer_helpers.zig").setupLoweringAnalyzerFixture;

// The host target triple differs between machines, so the expected modules use a fixed one.
const test_target_triple = "x86_64-unknown-linux-gnu";

const LlvmIrCodeGeneratorFixture = struct {
    analyzed_program: *const AnalyzedProgram,
    llvm_ir_code_generator: *LlvmIrCodeGenerator,
};

pub fn setupLlvmIrCodeGeneratorFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !LlvmIrCodeGeneratorFixture {
    const arena = arena_state.allocator();
    const lowering_analyzer_fixture = try setupLoweringAnalyzerFixture(arena_state, source);

    const function_symbol_generator = try arena.create(llvm_codegen.FunctionSymbolGenerator);
    function_symbol_generator.* = llvm_codegen.FunctionSymbolGenerator.init(arena);
    const function_ir_builder = try arena.create(llvm_codegen.FunctionIrBuilder);
    function_ir_builder.* = llvm_codegen.FunctionIrBuilder.init(arena);
    const runtime_call_emitter = try arena.create(llvm_codegen.RuntimeCallEmitter);
    runtime_call_emitter.* = llvm_codegen.RuntimeCallEmitter.init(arena);
    const runtime_symbol_renderer = try arena.create(llvm_codegen.RuntimeSymbolRenderer);
    runtime_symbol_renderer.* = llvm_codegen.RuntimeSymbolRenderer.init(arena);
    const string_literal_renderer = try arena.create(llvm_codegen.StringLiteralRenderer);
    string_literal_renderer.* = llvm_codegen.StringLiteralRenderer.init(arena);
    const string_literal_pool = try arena.create(llvm_codegen.StringLiteralPool);
    string_literal_pool.* = llvm_codegen.StringLiteralPool.init(arena);
    const string_literal_emitter = try arena.create(llvm_codegen.StringLiteralEmitter);
    string_literal_emitter.* = llvm_codegen.StringLiteralEmitter.init(arena);
    const structure_type_renderer = try arena.create(llvm_codegen.StructureTypeRenderer);
    structure_type_renderer.* = llvm_codegen.StructureTypeRenderer.init(arena);
    const union_type_renderer = try arena.create(llvm_codegen.UnionTypeRenderer);
    union_type_renderer.* = llvm_codegen.UnionTypeRenderer.init(arena);

    const node_emitter = try arena.create(llvm_codegen.NodeEmitter);
    node_emitter.* = llvm_codegen.NodeEmitter.init(
        arena,
        function_symbol_generator,
        function_ir_builder,
        runtime_call_emitter,
        string_literal_pool,
        string_literal_emitter,
    );
    const function_emitter = try arena.create(llvm_codegen.FunctionEmitter);
    function_emitter.* = llvm_codegen.FunctionEmitter.init(
        arena,
        function_symbol_generator,
        function_ir_builder,
        runtime_call_emitter,
        node_emitter,
    );
    const llvm_module_renderer = try arena.create(llvm_codegen.rendering.LlvmModuleRenderer);
    llvm_module_renderer.* = llvm_codegen.rendering.LlvmModuleRenderer.init(
        arena,
        test_target_triple,
        function_emitter,
        runtime_call_emitter,
        runtime_symbol_renderer,
        string_literal_pool,
        string_literal_renderer,
        structure_type_renderer,
        union_type_renderer,
    );

    const llvm_ir_code_generator = try arena.create(LlvmIrCodeGenerator);
    llvm_ir_code_generator.* = LlvmIrCodeGenerator.init(lowering_analyzer_fixture.lowering_analyzer, llvm_module_renderer);

    return .{
        .analyzed_program = lowering_analyzer_fixture.analyzed_program,
        .llvm_ir_code_generator = llvm_ir_code_generator,
    };
}
