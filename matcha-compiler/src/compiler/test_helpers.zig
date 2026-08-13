const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");

pub const TestError = error{UnexpectedNodeKind};

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
    typed_program: semantic_analysis.AnalyzedProgram,

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
    const runtime_representation_analyzer = semantic_analysis.runtime_representation.RuntimeRepresentationAnalyzer.init(allocator);
    var analyzer = semantic_analysis.SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
        runtime_representation_analyzer,
    );
    const typed_program = try analyzer.analyzeProgram(&parsed.program);

    return .{
        .parsed = parsed,
        .typed_program = typed_program,
    };
}

pub fn expectDeclarationNode(node: *const ast.Node) TestError!ast.Declaration {
    return switch (node.kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectBlockNode(node: *const ast.Node) TestError!ast.Block {
    return switch (node.kind) {
        .Block => |block| block,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectWhileNode(node: *const ast.Node) TestError!ast.While {
    return switch (node.kind) {
        .While => |while_statement| while_statement,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectForInNode(node: *const ast.Node) TestError!ast.ForIn {
    return switch (node.kind) {
        .ForIn => |for_in| for_in,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectItemDefinitionNode(node: *const ast.Node) TestError!ast.ItemDefinition {
    return switch (node.kind) {
        .ItemDefinition => |item_definition| item_definition,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectFunctionItem(node: *const ast.Node) TestError!ast.Function {
    const item_definition = try expectItemDefinitionNode(node);
    return switch (item_definition.item) {
        .Function => |definition| definition,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectCallExpressionNode(node: *const ast.Node) TestError!ast.CallExpression {
    return switch (node.kind) {
        .CallExpression => |call_expression| call_expression,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectMatchExpressionNode(node: *const ast.Node) TestError!ast.MatchExpression {
    return switch (node.kind) {
        .MatchExpression => |match_expression| match_expression,
        else => return TestError.UnexpectedNodeKind,
    };
}

pub fn expectIndexAccessNode(node: *const ast.Node) TestError!ast.IndexAccess {
    return switch (node.kind) {
        .IndexAccess => |index_access| index_access,
        else => return TestError.UnexpectedNodeKind,
    };
}
