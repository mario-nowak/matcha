const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");

pub const ParsedProgram = struct {
    arena: std.heap.ArenaAllocator,
    program: ast.Program,

    pub fn allocator(self: *ParsedProgram) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *ParsedProgram) void {
        self.arena.deinit();
    }
};

pub const AnalyzedProgram = struct {
    parsed: ParsedProgram,
    typed_program: typing.TypedProgram,

    pub fn allocator(self: *AnalyzedProgram) std.mem.Allocator {
        return self.parsed.allocator();
    }

    pub fn deinit(self: *AnalyzedProgram) void {
        self.parsed.deinit();
    }
};

pub fn parseProgram(source: []const u8) !ParsedProgram {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, source);

    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator, &diagnostic_store);
    const program = try parser.parse();

    return .{
        .arena = arena,
        .program = program,
    };
}

pub fn analyzeProgram(source: []const u8) !AnalyzedProgram {
    var parsed = try parseProgram(source);
    errdefer parsed.deinit();

    const allocator = parsed.allocator();
    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    const name_resolver = semantic_analysis.name_resolution.NameResolver.init(allocator, &diagnostic_store);
    const type_seeder = semantic_analysis.type_checking.TypeSeeder.init();
    const node_type_analyzer = semantic_analysis.type_checking.NodeTypeAnalyzer.init(allocator, &diagnostic_store);
    const type_checker = semantic_analysis.type_checking.TypeChecker.init(
        type_seeder,
        node_type_analyzer,
    );
    const structural_validator = semantic_analysis.control_flow_validation.StructuralValidator.init(&diagnostic_store);
    const exit_behavior_analyzer = semantic_analysis.control_flow_validation.ExitBehaviorAnalyzer.init(allocator, &diagnostic_store);
    const control_flow_validator = semantic_analysis.control_flow_validation.ControlFlowValidator.init(
        structural_validator,
        exit_behavior_analyzer,
    );
    var analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
    );
    const typed_program = try analyzer.validateProgram(&parsed.program);

    return .{
        .parsed = parsed,
        .typed_program = typed_program,
    };
}
