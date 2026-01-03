const std = @import("std");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const SemanticAnalyzer = @import("semantic_analysis/semantic_analyzer.zig").SemanticAnalyzer;
const llvmIrEmitter = @import("llvm_ir_emitter.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const commandLineArguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, commandLineArguments);
    const fileName = commandLineArguments[1];

    const cwd = std.fs.cwd();
    const fileContents = try cwd.readFileAlloc(allocator, fileName, 4096);
    defer allocator.free(fileContents);

    var lexerTest = lexer.Lexer.init(fileContents, allocator);
    defer lexerTest.deinit();

    var parserTest = parser.Parser.init(lexerTest, allocator);
    const program = try parserTest.parse();

    var semanticAnalyzer = SemanticAnalyzer.init(allocator);
    try semanticAnalyzer.validateProgram(&program);

    std.debug.print("Expression: {any}\n", .{program});

    // var llvmIrEmitterTest = llvmIrEmitter.LlvmIrEmitter.init(allocator);
    // const emitted = llvmIrEmitterTest.emitLlvmIr(expression);

    // var file = try std.fs.cwd().createFile("emission.ll", .{});
    // defer file.close();
    // _ = try file.write(emitted);

    // Print file contents
    // std.debug.print("{s}\n", .{fileContents});
}
