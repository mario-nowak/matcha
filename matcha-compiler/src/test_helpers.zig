const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const parsing = @import("parsing");
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

    var lexer = lexing.Lexer.init(owned_source, allocator);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator);
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
    const name_resolver = semantic_analysis.name_resolution.NameResolver.init(allocator);
    const type_checker = semantic_analysis.type_checking.TypeChecker.init(allocator);
    var analyzer = semantic_analysis.SemanticAnalyzer.init(name_resolver, type_checker);
    const typed_program = try analyzer.validateProgram(&parsed.program);

    return .{
        .parsed = parsed,
        .typed_program = typed_program,
    };
}
