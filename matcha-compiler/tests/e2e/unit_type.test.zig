const e2e = @import("helpers.zig");

test "the unit literal can be assigned to variables" {
    const source =
        \\val unit_variable: unit = unit;
    ;

    var result = try e2e.runSource("unit_literal_assignment.md", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}
