const semantic_analysis = @import("semantic_analysis");
const lowering_types = @import("lowering_types.zig");

pub const RuntimeRequirementsLowerer = struct {
    pub fn init() @This() {
        return .{};
    }

    pub fn lower(self: *const @This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.RuntimeRequirementsPlan {
        _ = self;
        _ = analyzed_program;
        return .{};
    }
};
