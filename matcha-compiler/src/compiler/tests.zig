const std = @import("std");

comptime {
    _ = @import("testing/expect.test.zig");
    _ = @import("lexing/lexer.test.zig");
    _ = @import("parsing/type_expression_parser.test.zig");
    _ = @import("parsing/parser.test.zig");
    _ = @import("pipeline.test.zig");
    _ = @import("semantic_analysis/control_flow/structural_validator.test.zig");
    _ = @import("semantic_analysis/control_flow/exit_behavior_analyzer.test.zig");
    _ = @import("semantic_analysis/name_resolution/name_resolver.test.zig");
    referenceAllTestsRecursive(@import("semantic_analysis/type_checking/node_type_analyzer.test.zig"));
    referenceAllTestsRecursive(@import("semantic_analysis/runtime_representation/runtime_representation_analyzer.test.zig"));
    _ = @import("semantic_analysis/semantic_analyzer.test.zig");
    _ = @import("llvm_codegen/lowering/call_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/member_access_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/place_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/binary_operation_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/structure_layout_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/function_layout_lowerer.test.zig");
    _ = @import("llvm_codegen/llvm_ir_code_generator.test.zig");
}

/// Test blocks inside nested structs are only analyzed when the struct is referenced.
/// This references every public container in a test file, so nested scopes need `pub`.
fn referenceAllTestsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |declaration| {
        const value = @field(T, declaration.name);
        if (@TypeOf(value) == type and @typeInfo(value) == .@"struct") {
            referenceAllTestsRecursive(value);
        }
    }
}
