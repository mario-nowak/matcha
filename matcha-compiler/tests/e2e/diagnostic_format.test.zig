const std = @import("std");
const e2e = @import("helpers.zig");

test "diagnostic format renders the full layout" {
    const file_path = "tests/e2e/programs/diagnostics/missing_declaration_semicolon.mt";

    var result = try e2e.runFile(file_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings(
        "error: expected ';' after declaration\n" ++
            " --> tests/e2e/programs/diagnostics/missing_declaration_semicolon.mt:2:1\n" ++
            "   |\n" ++
            " 2 | val y = 2;\n" ++
            "   |^^^\n\n",
        result.stderr,
    );
}
