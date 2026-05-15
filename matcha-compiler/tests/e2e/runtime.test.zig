const e2e = @import("helpers.zig");

test "array index out of bounds reports a runtime error" {
    const source =
        \\val xs = [1, 2];
        \\printInt(xs[3]);
    ;

    var result = try e2e.runSource("array_index_out_of_bounds.mt", source);
    defer result.deinit();

    try e2e.expectRuntimeError(&result, "runtime error: array index out of bounds");
}
