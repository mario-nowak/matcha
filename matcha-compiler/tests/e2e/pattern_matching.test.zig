const e2e = @import("helpers.zig");

test "pattern matching 1" {
    const source =
        \\item Offset = union { None, Horizontal: int, Vertical: int };
        \\val offset_1 = Offset.Horizontal(4);
        \\val result = match offset_1 {
        \\    .None => 0,
        \\    .Horizontal(value) => value,
        \\    .Vertical(value) => value,
        \\};
        \\printInt(result);
    ;

    var result = try e2e.runSource("control_flow_if_and_block.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "4\n");
}
