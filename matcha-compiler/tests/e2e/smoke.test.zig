const std = @import("std");
const e2e = @import("helpers.zig");

test "structure methods smoke test prints the inverted point" {
    const file_path = "tests/e2e/programs/point_structure_smoke.mt";

    var result = try e2e.runFile(file_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("Point { x = -3, y = -6 } (length: 45)\n", result.stdout);
}
