const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");

const ParserPipeline = struct {
    diagnostic_store: *diagnostics.DiagnosticStore,
    lexer: *lexing.Lexer,
    parser: *parsing.Parser,
};

pub fn setupParserPipeline(arena: *std.heap.ArenaAllocator, source: []const u8) !ParserPipeline {
    const allocator = arena.allocator();
    const diagnostic_store = try allocator.create(diagnostics.DiagnosticStore);
    diagnostic_store.* = diagnostics.DiagnosticStore.init(allocator);

    const lexer = try allocator.create(lexing.Lexer);
    lexer.* = lexing.Lexer.init(source, allocator, diagnostic_store);

    const parser = try allocator.create(parsing.Parser);
    parser.* = parsing.Parser.init(lexer.*, allocator, diagnostic_store);

    return .{
        .diagnostic_store = diagnostic_store,
        .lexer = lexer,
        .parser = parser,
    };
}
