const std = @import("std");
const diagnostics = @import("diagnostics");
const lexing = @import("lexing");

// The caller owns the arena that stores the source and tokens.
pub fn lex(allocator: std.mem.Allocator, source: []const u8) ![]lexing.Token {
    const owned_source = try allocator.dupe(u8, source);
    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var tokens = std.ArrayList(lexing.Token){};
    defer tokens.deinit(allocator);
    while (true) {
        const token = try lexer.next();
        try tokens.append(allocator, token);
        if (token.kind == .EndOfFile) break;
    }
    return tokens.toOwnedSlice(allocator);
}
