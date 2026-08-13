test {
    _ = @import("lexing/lexer.test.zig");
    _ = @import("parsing/type_expression_parser.test.zig");
    _ = @import("parsing/parser.test.zig");
    _ = @import("pipeline.test.zig");
    _ = @import("semantic_analysis/name_resolution/name_resolver.test.zig");
    _ = @import("semantic_analysis/semantic_analyzer.test.zig");
    _ = @import("llvm_codegen/lowering/call_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/member_access_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/place_lowerer.test.zig");
    _ = @import("llvm_codegen/lowering/binary_operation_lowerer.test.zig");
    _ = @import("llvm_codegen/llvm_ir_code_generator.test.zig");
}
