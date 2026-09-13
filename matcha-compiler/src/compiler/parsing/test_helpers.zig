const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !ast.Program {
    const owned_source = try allocator.dupe(u8, source);
    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator, &diagnostic_store);
    return parser.parse();
}
