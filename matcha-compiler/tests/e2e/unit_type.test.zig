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

test "unit return values in a function are evaluated" {
    const source =
        \\item printHelloWorld(): unit = {
        \\    return printString("Hello, world!");
        \\};
        \\printHelloWorld();
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

test "an array can be constructed with unit elements" {
    const source =
        \\val unit_array: unit[] = [unit, unit, unit];
        \\printInt(unit_array.length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "3\n");
}

test "an array of unit elements can be accessed" {
    const source =
        \\val unit_array: unit[] = [unit, unit, unit];
        \\val first_element: unit = unit_array[0];
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}

test "accessing an array of unit element out of bounds results in a panic" {
    const source =
        \\val unit_array: unit[] = [unit, unit, unit];
        \\val first_element: unit = unit_array[3];
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "runtime error: array index out of bounds\n  at line 2, column 37\n  index 3 is out of bounds for length 3\n");
}

test "the values of an array of unit elements are evaluated" {
    const source =
        \\val unit_array: unit[] = [
        \\    printString("Hello, world!"),
        \\    printString("Hello, world!"),
        \\    printString("Hello, world!")
        \\];
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\nHello, world!\nHello, world!\n");
}

test "an array of unit elements can be iterated over" {
    const source =
        \\val unit_array: unit[] = [unit, unit, unit];
        \\for element in unit_array {
        \\    printString("Hello, world!");
        \\}
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\nHello, world!\nHello, world!\n");
}

test "an array of unit elements can be appended to" {
    const source =
        \\var unit_array: unit[] = [unit, unit, unit];
        \\unit_array.append(unit);
        \\printInt(unit_array.length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "4\n");
}
