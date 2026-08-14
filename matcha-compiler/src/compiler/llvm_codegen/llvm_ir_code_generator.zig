const semantic_analysis = @import("semantic_analysis");

const lowering = @import("lowering");
const rendering = @import("rendering");

pub const LlvmIrCodeGenerator = struct {
    lowering_analyzer: *lowering.LoweringAnalyzer,
    module_renderer: *rendering.LlvmModuleRenderer,

    pub fn init(
        lowering_analyzer: *lowering.LoweringAnalyzer,
        module_renderer: *rendering.LlvmModuleRenderer,
    ) @This() {
        return .{
            .lowering_analyzer = lowering_analyzer,
            .module_renderer = module_renderer,
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn generateLlvmIr(
        self: *@This(),
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
    ) []const u8 {
        const lowered_program = self.lowering_analyzer.lowerProgram(analyzed_program);
        return self.module_renderer.renderLlvmIr(&lowered_program);
    }
};
