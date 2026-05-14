const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const semantic_analysis = @import("semantic_analysis");
const emission = @import("emission");

pub fn emitLlvmIrFromFile(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(input_path, .{});
    defer file.close();

    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var lexer = lexing.Lexer.init(file_contents, allocator);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator);
    const program = try parser.parse();

    const name_resolver = semantic_analysis.name_resolution.NameResolver.init(allocator);
    const type_checker = semantic_analysis.type_checking.TypeChecker.init(allocator);
    const control_flow_validator = semantic_analysis.control_flow_validation.ControlFlowValidator.init(allocator);
    var semantic_analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
    );
    const typed_program = try semantic_analyzer.validateProgram(&program);

    var llvm_ir_emitter = emission.LlvmIrEmitter.init(allocator);
    return llvm_ir_emitter.emitLlvmIr(&typed_program);
}

pub fn emitFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: ?[]const u8) ![]const u8 {
    const llvm_ir = try emitLlvmIrFromFile(allocator, input_path);
    const resolved_output_path = output_path orelse try defaultLlvmOutputPath(allocator, input_path);
    try writeFile(resolved_output_path, llvm_ir);
    try std.fs.File.stdout().deprecatedWriter().print("wrote {s}\n", .{resolved_output_path});
    return resolved_output_path;
}

pub fn defaultLlvmOutputPath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}-emission.ll", .{stemWithoutMatchaExtension(input_path)});
}

pub fn defaultBinaryOutputPath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return allocator.dupe(u8, stemWithoutMatchaExtension(input_path));
}

pub fn writeFile(path: []const u8, contents: []const u8) !void {
    const cwd = std.fs.cwd();
    if (std.fs.path.dirname(path)) |directory| {
        try cwd.makePath(directory);
    }

    var file = try cwd.createFile(path, .{});
    defer file.close();
    try file.writeAll(contents);
}

fn stemWithoutMatchaExtension(input_path: []const u8) []const u8 {
    const extension = std.fs.path.extension(input_path);
    if (std.mem.eql(u8, extension, ".mt")) {
        return input_path[0 .. input_path.len - extension.len];
    }
    return input_path;
}

test "default llvm output path strips final matcha extension" {
    const output_path = try defaultLlvmOutputPath(std.testing.allocator, "examples/v0.1/learning-matcha.mt");
    defer std.testing.allocator.free(output_path);

    try std.testing.expectEqualStrings("examples/v0.1/learning-matcha-emission.ll", output_path);
}

test "default binary output path strips final matcha extension" {
    const output_path = try defaultBinaryOutputPath(std.testing.allocator, "examples/customer-import-audit.mt");
    defer std.testing.allocator.free(output_path);

    try std.testing.expectEqualStrings("examples/customer-import-audit", output_path);
}
