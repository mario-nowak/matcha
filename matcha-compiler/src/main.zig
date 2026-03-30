const std = @import("std");

const matcha = @import("matcha");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const command_line_arguments = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, command_line_arguments);
    const fileName = command_line_arguments[1];

    const cwd = std.fs.cwd();
    const file_contents = try cwd.readFileAlloc(allocator, fileName, 4096);
    defer allocator.free(file_contents);

    var lexer = matcha.lexing.Lexer.init(file_contents, allocator);
    defer lexer.deinit();

    var parser = matcha.parsing.Parser.init(lexer, allocator);
    const program = try parser.parse();

    const name_resolver = matcha.semantic_analysis.name_resolution.NameResolver.init(allocator);
    const type_checker = matcha.semantic_analysis.type_checking.TypeChecker.init(allocator);
    var semantic_analyzer = matcha.semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
    );
    const typed_program = try semantic_analyzer.validateProgram(&program);

    var llvm_ir_emitter = matcha.emission.LlvmIrEmitter.init(allocator);
    const emitted = llvm_ir_emitter.emitLlvmIr(&typed_program);

    var file = try std.fs.cwd().createFile("emission.ll", .{});
    defer file.close();
    _ = try file.write(emitted);
}
