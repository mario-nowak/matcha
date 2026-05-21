pub const SemanticAnalyzer = @import("semantic_analyzer.zig").SemanticAnalyzer;
pub const AnalyzedProgram = @import("analyzed_program.zig").AnalyzedProgram;
pub const name_resolution = @import("name_resolution/module.zig");
pub const type_checking = @import("type_checking/module.zig");
pub const control_flow_validation = @import("control_flow/module.zig");
pub const runtime_representation = @import("runtime_representation/module.zig");
