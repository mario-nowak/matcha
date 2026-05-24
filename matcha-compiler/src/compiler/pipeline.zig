const std = @import("std");
const builtin = @import("builtin");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const emission = @import("emission");

pub fn emitLlvmIrFromFile(allocator: std.mem.Allocator, input_path: []const u8, diagnostic_store: *diagnostics.DiagnosticStore) ![]const u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(input_path, .{});
    defer file.close();

    const file_contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_contents);

    var lexer = lexing.Lexer.init(file_contents, allocator, diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator, diagnostic_store);
    const program = try parser.parse();

    const name_resolver = semantic_analysis.name_resolution.NameResolver.init(allocator, diagnostic_store);
    const type_seeder = semantic_analysis.type_checking.TypeSeeder.init();
    const node_type_analyzer = semantic_analysis.type_checking.NodeTypeAnalyzer.init(allocator, diagnostic_store);
    const type_checker = semantic_analysis.type_checking.TypeChecker.init(
        type_seeder,
        node_type_analyzer,
    );
    const structural_validator = semantic_analysis.control_flow_validation.StructuralValidator.init(diagnostic_store);
    const exit_behavior_analyzer = semantic_analysis.control_flow_validation.ExitBehaviorAnalyzer.init(allocator, diagnostic_store);
    const control_flow_validator = semantic_analysis.control_flow_validation.ControlFlowValidator.init(
        structural_validator,
        exit_behavior_analyzer,
    );
    const runtime_representation_analyzer = semantic_analysis.runtime_representation.RuntimeRepresentationAnalyzer.init(allocator);
    var semantic_analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
        runtime_representation_analyzer,
    );
    const typed_program = try semantic_analyzer.analyzeProgram(&program);

    const function_symbol_generator = emission.FunctionSymbolGenerator.init(allocator);
    const function_ir_builder = emission.FunctionIrBuilder.init(allocator);
    const symbol_generator = emission.SymbolGenerator.init(allocator);
    const runtime_call_emitter = emission.RuntimeCallEmitter.init(allocator);
    const runtime_symbol_emitter = emission.RuntimeSymbolEmitter.init(allocator);
    const string_literal_renderer = emission.StringLiteralRenderer.init(allocator);
    const structure_type_definition_renderer = emission.StructureTypeDefinitionRenderer.init(allocator);
    var llvm_ir_emitter = emission.LlvmIrEmitter.init(
        allocator,
        getLlvmTargetTriple(),
        function_symbol_generator,
        function_ir_builder,
        symbol_generator,
        runtime_call_emitter,
        runtime_symbol_emitter,
        string_literal_renderer,
        structure_type_definition_renderer,
    );
    return llvm_ir_emitter.emitLlvmIr(&typed_program);
}

pub fn emitFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: ?[]const u8, diagnostic_store: *diagnostics.DiagnosticStore) ![]const u8 {
    const llvm_ir = try emitLlvmIrFromFile(allocator, input_path, diagnostic_store);
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

pub fn getLlvmTargetTriple() []const u8 {
    return switch (builtin.os.tag) {
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "arm64-apple-macosx26.4.1",
            .x86_64 => "x86_64-apple-macosx26.4.1",
            else => @panic("unsupported macOS architecture"),
        },
        .linux => switch (builtin.cpu.arch) {
            .x86_64 => "x86_64-unknown-linux-gnu",
            .aarch64 => "aarch64-unknown-linux-gnu",
            else => @panic("unsupported Linux architecture"),
        },
        else => @panic("unsupported host platform"),
    };
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
