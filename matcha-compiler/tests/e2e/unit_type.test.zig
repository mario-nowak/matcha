const e2e = @import("helpers.zig");

test "the unit literal can be assigned to variables" {
    const source =
        \\val unit_variable: unit = unit;
    ;

    var result = try e2e.runSource("unit_literal_assignment.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}

test "the unit literal can be returned from functions" {
    const source =
        \\item printHelloWorld(): unit = {
        \\    printString("Hello, world!");
        \\    return unit;
        \\};
        \\var result: unit = printHelloWorld();
    ;

    var result = try e2e.runSource("unit_literal_return.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\n");
}

test "a function that returns unit can be called without using its return value" {
    const source =
        \\item printHelloWorld(): unit = {
        \\    printString("Hello, world!");
        \\    return unit;
        \\};
        \\printHelloWorld();
    ;

    var result = try e2e.runSource("unit_literal_return.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\n");
}

test "a block that evaluates to unit can be used as an expression" {
    const source =
        \\val x = {
        \\    printString("Hello, world!");
        \\};
    ;

    var result = try e2e.runSource("unit_literal_block.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\n");
}
