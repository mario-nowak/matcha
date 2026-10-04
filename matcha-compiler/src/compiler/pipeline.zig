const std = @import("std");
const builtin = @import("builtin");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const llvm_codegen = @import("llvm_codegen");

pub fn generateLlvmIrFromFile(
    arena: std.mem.Allocator,
    input_path: []const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) ![]const u8 {
    const file_contents = readInputFile(arena, input_path) catch |read_error| {
        try std.fs.File.stderr().deprecatedWriter().print("error: cannot read input file '{s}': {s}\n", .{ input_path, @errorName(read_error) });
        return error.InputFileUnreadable;
    };

    const lexer = lexing.Lexer.init(file_contents, arena, diagnostic_store);

    var parser = parsing.Parser.init(lexer, arena, diagnostic_store);
    const program = try parser.parse();

    const name_resolver = semantic_analysis.name_resolution.NameResolver.init(arena, diagnostic_store);
    const node_type_analyzer = semantic_analysis.type_checking.NodeTypeAnalyzer.init(arena, diagnostic_store);
    const structural_validator = semantic_analysis.control_flow_validation.StructuralValidator.init(diagnostic_store);
    const exit_behavior_analyzer = semantic_analysis.control_flow_validation.ExitBehaviorAnalyzer.init(
        arena,
        diagnostic_store,
    );
    const control_flow_validator = semantic_analysis.control_flow_validation.ControlFlowValidator.init(
        structural_validator,
        exit_behavior_analyzer,
    );
    const runtime_representation_analyzer = semantic_analysis.runtime_representation.RuntimeRepresentationAnalyzer.init(
        arena,
    );
    var semantic_analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        node_type_analyzer,
        control_flow_validator,
        runtime_representation_analyzer,
    );
    const analyzed_program = try semantic_analyzer.analyzeProgram(&program);

    var llvm_type_table_lowerer = llvm_codegen.lowering.LlvmTypeTableLowerer.init(arena);
    var call_lowerer = llvm_codegen.lowering.CallLowerer.init(arena);
    var member_access_lowerer = llvm_codegen.lowering.MemberAccessLowerer.init(arena);
    var binary_operation_lowerer = llvm_codegen.lowering.BinaryOperationLowerer.init(arena);
    var place_lowerer = llvm_codegen.lowering.PlaceLowerer.init(arena);
    var structure_layout_lowerer = llvm_codegen.lowering.StructureLayoutLowerer.init(arena);
    var union_layout_lowerer = llvm_codegen.lowering.UnionLayoutLowerer.init(arena);
    var function_layout_lowerer = llvm_codegen.lowering.FunctionLayoutLowerer.init(arena);

    var lowering_analyzer = llvm_codegen.lowering.LoweringAnalyzer.init(
        &llvm_type_table_lowerer,
        &call_lowerer,
        &member_access_lowerer,
        &binary_operation_lowerer,
        &place_lowerer,
        &structure_layout_lowerer,
        &union_layout_lowerer,
        &function_layout_lowerer,
    );
    var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena);
    var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena);
    var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena);
    var runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena);
    var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(arena);
    var string_literal_pool = llvm_codegen.StringLiteralPool.init(arena);
    var string_literal_emitter = llvm_codegen.StringLiteralEmitter.init(arena);
    var structure_type_renderer = llvm_codegen.StructureTypeRenderer.init(arena);
    var union_type_renderer = llvm_codegen.UnionTypeRenderer.init(arena);

    var node_emitter = llvm_codegen.NodeEmitter.init(
        arena,
        &function_symbol_generator,
        &function_ir_builder,
        &runtime_call_emitter,
        &string_literal_pool,
        &string_literal_emitter,
    );

    var function_emitter = llvm_codegen.FunctionEmitter.init(
        arena,
        &function_symbol_generator,
        &function_ir_builder,
        &runtime_call_emitter,
        &node_emitter,
    );

    var llvm_module_renderer = llvm_codegen.rendering.LlvmModuleRenderer.init(
        arena,
        getLlvmTargetTriple(),
        &function_emitter,
        &runtime_call_emitter,
        &runtime_symbol_renderer,
        &string_literal_pool,
        &string_literal_renderer,
        &structure_type_renderer,
        &union_type_renderer,
    );

    var llvm_ir_code_generator = llvm_codegen.LlvmIrCodeGenerator.init(
        &lowering_analyzer,
        &llvm_module_renderer,
    );

    return llvm_ir_code_generator.generateLlvmIr(&analyzed_program);
}

pub fn emitFile(
    arena: std.mem.Allocator,
    input_path: []const u8,
    output_path: ?[]const u8,
    diagnostic_store: *diagnostics.DiagnosticStore,
) !void {
    const llvm_ir = try generateLlvmIrFromFile(arena, input_path, diagnostic_store);
    const resolved_output_path = output_path orelse try getDefaultLlvmOutputPath(arena, input_path);
    writeFile(resolved_output_path, llvm_ir) catch |write_error| {
        try std.fs.File.stderr().deprecatedWriter().print("error: cannot write output file '{s}': {s}\n", .{ resolved_output_path, @errorName(write_error) });
        return error.OutputFileUnwritable;
    };
    try std.fs.File.stdout().deprecatedWriter().print("wrote {s}\n", .{resolved_output_path});
}

pub fn getDefaultLlvmOutputPath(arena: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        arena,
        "{s}-llvm-codegen.ll",
        .{stemWithoutMatchaExtension(input_path)},
    );
}

pub fn getDefaultBinaryOutputPath(arena: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    return arena.dupe(u8, stemWithoutMatchaExtension(input_path));
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

fn readInputFile(arena: std.mem.Allocator, input_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();
    return file.readToEndAlloc(arena, std.math.maxInt(usize));
}

fn stemWithoutMatchaExtension(input_path: []const u8) []const u8 {
    const extension = std.fs.path.extension(input_path);
    if (std.mem.eql(u8, extension, ".mt")) {
        return input_path[0 .. input_path.len - extension.len];
    }
    return input_path;
}
