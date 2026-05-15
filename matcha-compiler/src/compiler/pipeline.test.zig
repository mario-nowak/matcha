const std = @import("std");
const pipeline = @import("compiler").pipeline;

test "default llvm output path strips final matcha extension" {
    const input_path = "examples/v0.1/learning-matcha.mt";

    const output_path = try pipeline.defaultLlvmOutputPath(std.testing.allocator, input_path);
    defer std.testing.allocator.free(output_path);

    try std.testing.expectEqualStrings("examples/v0.1/learning-matcha-emission.ll", output_path);
}

test "default binary output path strips final matcha extension" {
    const input_path = "examples/customer-import-audit.mt";

    const output_path = try pipeline.defaultBinaryOutputPath(std.testing.allocator, input_path);
    defer std.testing.allocator.free(output_path);

    try std.testing.expectEqualStrings("examples/customer-import-audit", output_path);
}
