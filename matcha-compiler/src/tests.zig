test {
    _ = @import("lexing/lexer.test.zig");
    _ = @import("parsing/parser.test.zig");
    _ = @import("semantic_analysis/semantic_analyzer.test.zig");
    _ = @import("emission/llvm_ir_emitter.test.zig");
}
