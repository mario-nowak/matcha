test {
    _ = @import("lexing/lexer.test.zig");
    _ = @import("parsing/type_expression_parser.test.zig");
    _ = @import("parsing/parser.test.zig");
    _ = @import("pipeline.test.zig");
    _ = @import("semantic_analysis/name_resolution/name_resolver.test.zig");
    _ = @import("semantic_analysis/semantic_analyzer.test.zig");
    _ = @import("emission/call_lowerer.test.zig");
    _ = @import("emission/lowering_decisions.test.zig");
    _ = @import("emission/llvm_ir_emitter.test.zig");
}
