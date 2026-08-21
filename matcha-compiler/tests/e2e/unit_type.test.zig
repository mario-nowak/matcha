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

test "an element of an array of unit elements can be assigned to" {
    const source =
        \\var unit_array: unit[] = [unit, unit, unit];
        \\unit_array[1] = printString("evaluated");
        \\printInt(unit_array.length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "evaluated\n3\n");
}

test "assigning to an element of an array of unit elements out of bounds results in a panic" {
    const source =
        \\var unit_array: unit[] = [unit, unit, unit];
        \\unit_array[3] = unit;
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectRuntimeError(&result, "runtime error: array index out of bounds");
}

test "the elements of an array of unit elements can be used in a for-in loop" {
    const source =
        \\val unit_array: unit[] = [unit, unit, unit];
        \\for element in unit_array {
        \\    val x: unit = element;
        \\    printString("iterated");
        \\}
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "iterated\niterated\niterated\n");
}

test "an empty array of unit elements can be appended to" {
    const source =
        \\var unit_array: unit[] = [];
        \\unit_array.append(unit);
        \\unit_array.append(unit);
        \\printInt(unit_array.length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "2\n");
}

test "the argument of an append to an array of unit elements is evaluated" {
    const source =
        \\var unit_array: unit[] = [unit];
        \\unit_array.append(printString("evaluated"));
        \\printInt(unit_array.length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "evaluated\n2\n");
}

test "an array of unit elements can be passed to and returned from functions" {
    const source =
        \\item makeArray(): unit[] = {
        \\    return [unit, unit];
        \\};
        \\item countOf(array: unit[]): int = {
        \\    return array.length;
        \\};
        \\printInt(countOf(makeArray()));
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "2\n");
}

test "an array of arrays of unit elements can be constructed and accessed" {
    const source =
        \\val nested: unit[][] = [[unit], [unit, unit]];
        \\printInt(nested[1].length);
    ;

    var result = try e2e.runSource("unit_literal_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "2\n");
}

test "fields of structures can be of unit type" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\val instance: UnitStruct = .{ field = unit };
    ;

    var result = try e2e.runSource("unit_literal_struct.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}

test "structures with only unit type fields can have functions" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\
        \\    item printSomething(self: UnitStruct, something: string): unit = {
        \\        printString(something);
        \\    };
        \\};
        \\val instance: UnitStruct = .{ field = unit };
        \\instance.printSomething("Hello, world!");
    ;

    var result = try e2e.runSource("unit_literal_struct.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\n");
}

test "structures can have fields with unit type and fields of other types" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    field: unit;
        \\    other_field: int;
        \\};
        \\val instance: MixedUnitStruct = .{ field = unit, other_field = 42 };
    ;

    var result = try e2e.runSource("unit_literal_struct.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}
