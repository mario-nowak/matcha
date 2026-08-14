const std = @import("std");
const builtin = @import("builtin");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");

pub fn generateLlvmIrFromFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) ![]const u8 {
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
    const exit_behavior_analyzer = semantic_analysis.control_flow_validation.ExitBehaviorAnalyzer.init(
        allocator,
        diagnostic_store,
    );
    const control_flow_validator = semantic_analysis.control_flow_validation.ControlFlowValidator.init(
        structural_validator,
        exit_behavior_analyzer,
    );
    const runtime_representation_analyzer = semantic_analysis.runtime_representation.RuntimeRepresentationAnalyzer.init(
        allocator,
    );
    var semantic_analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
        runtime_representation_analyzer,
    );
    const analyzed_program = try semantic_analyzer.analyzeProgram(&program);

    var llvm_type_table_lowerer = llvm_codegen.lowering.LlvmTypeTableLowerer.init(allocator);
    defer llvm_type_table_lowerer.deinit();
    var structure_symbol_lowerer = llvm_codegen.lowering.StructureSymbolLowerer.init(allocator);
    defer structure_symbol_lowerer.deinit();
    var call_lowerer = llvm_codegen.lowering.CallLowerer.init(allocator);
    defer call_lowerer.deinit();
    var member_access_lowerer = llvm_codegen.lowering.MemberAccessLowerer.init(allocator);
    defer member_access_lowerer.deinit();
    var binary_operation_lowerer = llvm_codegen.lowering.BinaryOperationLowerer.init(allocator);
    defer binary_operation_lowerer.deinit();
    var place_lowerer = llvm_codegen.lowering.PlaceLowerer.init(allocator);
    defer place_lowerer.deinit();
    var node_value_kind_lowerer = llvm_codegen.lowering.NodeValueKindLowerer.init(allocator);
    defer node_value_kind_lowerer.deinit();
    const runtime_requirements_lowerer = llvm_codegen.lowering.RuntimeRequirementsLowerer.init();
    defer runtime_requirements_lowerer.deinit();

    var lowering_analyzer = llvm_codegen.lowering.LoweringAnalyzer.init(
        &llvm_type_table_lowerer,
        &structure_symbol_lowerer,
        &call_lowerer,
        &member_access_lowerer,
        &binary_operation_lowerer,
        &place_lowerer,
        &node_value_kind_lowerer,
        &runtime_requirements_lowerer,
    );
    defer lowering_analyzer.deinit();
    var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(allocator);
    defer function_symbol_generator.deinit();
    var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(allocator);
    defer function_ir_builder.deinit();
    var symbol_generator = llvm_codegen.SymbolGenerator.init(allocator);
    defer symbol_generator.deinit();
    var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(allocator);
    defer runtime_call_emitter.deinit();
    var runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(allocator);
    defer runtime_symbol_renderer.deinit();
    var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(allocator);
    defer string_literal_renderer.deinit();
    var string_literal_pool = llvm_codegen.StringLiteralPool.init(allocator);
    defer string_literal_pool.deinit();
    var string_literal_emitter = llvm_codegen.StringLiteralEmitter.init(allocator);
    defer string_literal_emitter.deinit();
    var structure_type_renderer = llvm_codegen.StructureTypeRenderer.init(allocator);
    defer structure_type_renderer.deinit();

    var node_emitter = llvm_codegen.NodeEmitter.init(
        allocator,
        &function_symbol_generator,
        &function_ir_builder,
        &symbol_generator,
        &runtime_call_emitter,
        &string_literal_pool,
        &string_literal_emitter,
    );
    defer node_emitter.deinit();

    var function_emitter = llvm_codegen.FunctionEmitter.init(
        allocator,
        &function_symbol_generator,
        &function_ir_builder,
        &symbol_generator,
        &runtime_call_emitter,
        &node_emitter,
    );
    defer function_emitter.deinit();

    var llvm_module_renderer = llvm_codegen.rendering.LlvmModuleRenderer.init(
        allocator,
        getLlvmTargetTriple(),
        &function_emitter,
        &runtime_symbol_renderer,
        &string_literal_pool,
        &string_literal_renderer,
        &structure_type_renderer,
    );
    defer llvm_module_renderer.deinit();

    var llvm_ir_code_generator = llvm_codegen.LlvmIrCodeGenerator.init(
        &lowering_analyzer,
        &llvm_module_renderer,
    );
    defer llvm_ir_code_generator.deinit();

    return llvm_ir_code_generator.generateLlvmIr(&analyzed_program);
}

pub fn emitFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: ?[]const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) !void {
    const llvm_ir = try generateLlvmIrFromFile(allocator, input_path, diagnostic_store);
    const resolved_output_path = output_path orelse try getDefaultLlvmOutputPath(allocator, input_path);
    try writeFile(resolved_output_path, llvm_ir);
    try std.fs.File.stdout().deprecatedWriter().print("wrote {s}\n", .{resolved_output_path});
}

pub fn getDefaultLlvmOutputPath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}-llvm-codegen.ll",
        .{stemWithoutMatchaExtension(input_path)},
    );
}

pub fn getDefaultBinaryOutputPath(allocator: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return allocator.dupe(u8, stemWithoutMatchaExtension(input_path));
}

// The macOS version the compiler was built on. Baking it into the triple keeps
// the linked binaries consistent with libmatcha_runtime.a, which zig builds for
// the same native version in the same `zig build`.
const native_macos_version = if (builtin.os.tag == .macos)
blk: {
    const version = builtin.target.os.version_range.semver.min;
    break :blk std.fmt.comptimePrint("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });
} else "";

pub fn getLlvmTargetTriple() []const u8 {
    return switch (builtin.os.tag) {
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "arm64-apple-macosx" ++ native_macos_version,
            .x86_64 => "x86_64-apple-macosx" ++ native_macos_version,
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
