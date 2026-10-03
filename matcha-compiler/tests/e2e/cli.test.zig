const std = @import("std");
const e2e = @import("helpers.zig");

pub const Matcha = struct {
    pub const run = struct {
        pub const input_files = struct {
            test "reports an input file that does not exist" {
                const file_path = "tests/e2e/programs/does_not_exist.mt";

                var result = try e2e.runFile(file_path);
                defer result.deinit();

                try std.testing.expectEqual(@as(u32, 1), result.exit_code);
                try e2e.expectContains(result.stderr, "error: cannot read input file 'tests/e2e/programs/does_not_exist.mt': FileNotFound");
            }
        };
    };
};
