pub const LlvmModuleRenderer = @import("llvm_module_renderer.zig").LlvmModuleRenderer;
pub const FunctionRenderer = @import("function_renderer.zig").FunctionRenderer;
pub const NodeRenderer = @import("node_renderer.zig").NodeRenderer;
pub const Environment = @import("node_renderer.zig").Environment;
pub const EmissionResult = @import("node_renderer.zig").EmissionResult;

pub const lowering = @import("lowering");
pub const function_emission = @import("function_emission");
pub const FunctionIrBuilder = function_emission.FunctionIrBuilder;
pub const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;

pub const runtime_emission = @import("runtime_emission");
pub const RuntimeCallEmitter = runtime_emission.RuntimeCallEmitter;
pub const RuntimeSymbolEmitter = runtime_emission.RuntimeSymbolEmitter;
pub const RuntimeRequirements = runtime_emission.RuntimeRequirements;

pub const StringLiteralRenderer = @import("string_literal_renderer.zig").StringLiteralRenderer;
pub const SymbolGenerator = @import("symbol_generator.zig").SymbolGenerator;
pub const StructureTypeDefinitionRenderer = @import("structure_type_definition_renderer.zig").StructureTypeDefinitionRenderer;

pub const llvm_type = lowering.llvm_type;
