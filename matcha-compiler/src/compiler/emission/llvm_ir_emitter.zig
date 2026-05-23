const std = @import("std");
const semantic_analysis = @import("semantic_analysis");

const lowering = @import("lowering");
const rendering = @import("rendering");

const FunctionIrBuilder = rendering.FunctionIrBuilder;
const FunctionSymbolGenerator = rendering.FunctionSymbolGenerator;
const RuntimeCallEmitter = rendering.RuntimeCallEmitter;
const RuntimeSymbolEmitter = rendering.RuntimeSymbolEmitter;
const StringLiteralRenderer = rendering.StringLiteralRenderer;
const StructureTypeDefinitionRenderer = rendering.StructureTypeDefinitionRenderer;
const SymbolGenerator = rendering.SymbolGenerator;

pub const LlvmIrEmitter = struct {
    lowering_analyzer: lowering.LoweringAnalyzer,
    module_renderer: rendering.LlvmModuleRenderer,

    pub fn init(
        allocator: std.mem.Allocator,
        target_triple: []const u8,
        function_symbol_generator: FunctionSymbolGenerator,
        function_ir_builder: FunctionIrBuilder,
        symbol_generator: SymbolGenerator,
        runtime_call_emitter: RuntimeCallEmitter,
        runtime_symbol_emitter: RuntimeSymbolEmitter,
        string_literal_renderer: StringLiteralRenderer,
        structure_type_definition_renderer: StructureTypeDefinitionRenderer,
    ) @This() {
        return .{
            .lowering_analyzer = lowering.LoweringAnalyzer.init(allocator),
            .module_renderer = rendering.LlvmModuleRenderer.init(
                allocator,
                target_triple,
                function_symbol_generator,
                function_ir_builder,
                symbol_generator,
                runtime_call_emitter,
                runtime_symbol_emitter,
                string_literal_renderer,
                structure_type_definition_renderer,
            ),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lowering_analyzer.deinit();
        self.module_renderer.deinit();
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const semantic_analysis.AnalyzedProgram) []const u8 {
        const lowered_program = self.lowering_analyzer.analyzeProgram(typed_program);
        return self.module_renderer.emitLlvmIr(&lowered_program);
    }
};
