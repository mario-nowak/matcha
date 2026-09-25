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
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !LlvmIrCodeGeneratorFixture {
    const allocator = arena.allocator();
    const lowering_analyzer_fixture = try setupLoweringAnalyzerFixture(arena, source);

    const function_symbol_generator = try allocator.create(llvm_codegen.FunctionSymbolGenerator);
    function_symbol_generator.* = llvm_codegen.FunctionSymbolGenerator.init(allocator);
    const function_ir_builder = try allocator.create(llvm_codegen.FunctionIrBuilder);
    function_ir_builder.* = llvm_codegen.FunctionIrBuilder.init(allocator);
    const symbol_generator = try allocator.create(llvm_codegen.SymbolGenerator);
    symbol_generator.* = llvm_codegen.SymbolGenerator.init(allocator);
    const runtime_call_emitter = try allocator.create(llvm_codegen.RuntimeCallEmitter);
    runtime_call_emitter.* = llvm_codegen.RuntimeCallEmitter.init(allocator);
    const runtime_symbol_renderer = try allocator.create(llvm_codegen.RuntimeSymbolRenderer);
    runtime_symbol_renderer.* = llvm_codegen.RuntimeSymbolRenderer.init(allocator);
    const string_literal_renderer = try allocator.create(llvm_codegen.StringLiteralRenderer);
    string_literal_renderer.* = llvm_codegen.StringLiteralRenderer.init(allocator);
    const string_literal_pool = try allocator.create(llvm_codegen.StringLiteralPool);
    string_literal_pool.* = llvm_codegen.StringLiteralPool.init(allocator);
    const string_literal_emitter = try allocator.create(llvm_codegen.StringLiteralEmitter);
    string_literal_emitter.* = llvm_codegen.StringLiteralEmitter.init(allocator);
    const structure_type_renderer = try allocator.create(llvm_codegen.StructureTypeRenderer);
    structure_type_renderer.* = llvm_codegen.StructureTypeRenderer.init(allocator);

    const node_emitter = try allocator.create(llvm_codegen.NodeEmitter);
    node_emitter.* = llvm_codegen.NodeEmitter.init(
        allocator,
        function_symbol_generator,
        function_ir_builder,
        symbol_generator,
        runtime_call_emitter,
        string_literal_pool,
        string_literal_emitter,
    );
    const function_emitter = try allocator.create(llvm_codegen.FunctionEmitter);
    function_emitter.* = llvm_codegen.FunctionEmitter.init(
        allocator,
        function_symbol_generator,
        function_ir_builder,
        symbol_generator,
        runtime_call_emitter,
        node_emitter,
    );
    const llvm_module_renderer = try allocator.create(llvm_codegen.rendering.LlvmModuleRenderer);
    llvm_module_renderer.* = llvm_codegen.rendering.LlvmModuleRenderer.init(
        allocator,
        test_target_triple,
        function_emitter,
        runtime_call_emitter,
        runtime_symbol_renderer,
        string_literal_pool,
        string_literal_renderer,
        structure_type_renderer,
    );

    const llvm_ir_code_generator = try allocator.create(LlvmIrCodeGenerator);
    llvm_ir_code_generator.* = LlvmIrCodeGenerator.init(lowering_analyzer_fixture.lowering_analyzer, llvm_module_renderer);

    return .{
        .analyzed_program = lowering_analyzer_fixture.analyzed_program,
        .llvm_ir_code_generator = llvm_ir_code_generator,
    };
}
