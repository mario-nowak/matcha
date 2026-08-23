const e2e = @import("helpers.zig");

test "the unit literal can be assigned to variables" {
    const source =
        \\val unit_variable: unit = unit;
    ;

    var result = try e2e.runSource("unit_literal_assignment.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}

test "variables with unit type can be reassigned and values are evaluated" {
    const source =
        \\var value: unit = unit;
        \\value = printString("evaluated");
    ;

    var result = try e2e.runSource("unit_variable_reassignment.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "evaluated\n");
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

test "if expressions can evaluate to unit" {
    const source =
        \\val then_result: unit = if true {
        \\    printString("then");
        \\} else {
        \\    printString("not then");
        \\};
        \\val else_result: unit = if false {
        \\    printString("not else");
        \\} else {
        \\    printString("else");
        \\};
    ;

    var result = try e2e.runSource("unit_if_expression.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "then\nelse\n");
}

test "match expressions can evaluate to unit" {
    const source =
        \\val true_result: unit = match true {
        \\    true => printString("true"),
        \\    false => printString("not true"),
        \\};
        \\val false_result: unit = match false {
        \\    true => printString("not false"),
        \\    false => printString("false"),
        \\};
    ;

    var result = try e2e.runSource("unit_match_expression.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "true\nfalse\n");
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

test "structures with only unit type fields can have type functions" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\
        \\    item printSomething(something: string): unit = {
        \\        printString(something);
        \\    };
        \\};
        \\UnitStruct.printSomething("Hello, world!");
    ;

    var result = try e2e.runSource("unit_literal_struct.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "Hello, world!\n");
}

test "functions can have parameters with types that don't have any runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\
        \\    item printSomething(self: UnitStruct, something: string): unit = {
        \\        printString(something);
        \\    };
        \\};
        \\
        \\item functionAcceptingUnitStruct(message: string, unit_struct: UnitStruct, additional_message: string): unit = {
        \\    unit_struct.printSomething(message);
        \\    printString(additional_message);
        \\};
        \\
        \\val instance: UnitStruct = .{ field = unit };
        \\functionAcceptingUnitStruct("message", instance, "additional_message");
    ;

    var result = try e2e.runSource("unit_literal_struct.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "message\nadditional_message\n");
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

test "represented structure fields after erased fields can be read" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    erased: unit;
        \\    value: int;
        \\};
        \\val instance: MixedUnitStruct = .{ erased = unit, value = 42 };
        \\printInt(instance.value);
    ;

    var result = try e2e.runSource("unit_structure_field_read.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "42\n");
}

test "represented structure fields after erased fields can be assigned" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    erased: unit;
        \\    value: int;
        \\};
        \\var instance: MixedUnitStruct = .{ erased = unit, value = 42 };
        \\instance.value = 43;
        \\printInt(instance.value);
    ;

    var result = try e2e.runSource("unit_structure_field_assignment.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "43\n");
}

test "erased structure fields can be read" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    erased: unit;
        \\    value: int;
        \\};
        \\val instance: MixedUnitStruct = .{ erased = unit, value = 42 };
        \\val erased: unit = instance.erased;
    ;

    var result = try e2e.runSource("erased_structure_field_read.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "");
}

test "erased structure fields can be assigned and values are evaluated" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    erased: unit;
        \\    value: int;
        \\};
        \\var instance: MixedUnitStruct = .{ erased = unit, value = 42 };
        \\instance.erased = printString("assigned");
        \\printInt(instance.value);
    ;

    var result = try e2e.runSource("erased_structure_field_assignment.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "assigned\n42\n");
}

test "represented fields separated by an erased field use compact runtime indices" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    first: int;
        \\    erased: unit;
        \\    second: int;
        \\};
        \\val instance: MixedUnitStruct = .{ first = 41, erased = unit, second = 42 };
        \\printInt(instance.first);
        \\printInt(instance.second);
    ;

    var result = try e2e.runSource("interleaved_unit_structure_fields.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "41\n42\n");
}

test "functions can return structures without runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\item makeUnitStruct(): UnitStruct = .{
        \\    field = printString("constructed"),
        \\};
        \\val instance: UnitStruct = makeUnitStruct();
    ;

    var result = try e2e.runSource("unit_structure_return.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "constructed\n");
}

test "arrays can contain structures without runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\var instances: UnitStruct[] = [UnitStruct { field = unit }, UnitStruct { field = unit }];
        \\instances.append(UnitStruct { field = printString("appended") });
        \\val first: UnitStruct = instances[0];
        \\printInt(instances.length);
    ;

    var result = try e2e.runSource("unit_structure_array.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "appended\n3\n");
}

test "multiple erased function arguments are evaluated in order" {
    const source =
        \\item selectValue(first: unit, value: int, second: unit): int = {
        \\    return value;
        \\};
        \\printInt(selectValue(
        \\    printString("first"),
        \\    42,
        \\    printString("second")
        \\));
    ;

    var result = try e2e.runSource("erased_function_argument_order.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "first\nsecond\n42\n");
}

test "structure fields can be constructed out of definition order when fields are erased" {
    const source =
        \\item MixedUnitStruct = structure {
        \\    first: int;
        \\    erased: unit;
        \\    second: int;
        \\};
        \\val instance: MixedUnitStruct = .{
        \\    second = 42,
        \\    erased = unit,
        \\    first = 41,
        \\};
        \\printInt(instance.first);
        \\printInt(instance.second);
    ;

    var result = try e2e.runSource("reordered_unit_structure_fields.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "41\n42\n");
}

test "if expressions can return structures without runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\item makeUnitStruct(message: string): UnitStruct = .{
        \\    field = printString(message),
        \\};
        \\val then_result: UnitStruct = if true {
        \\    makeUnitStruct("then")
        \\} else {
        \\    makeUnitStruct("not then")
        \\};
        \\val else_result: UnitStruct = if false {
        \\    makeUnitStruct("not else")
        \\} else {
        \\    makeUnitStruct("else")
        \\};
    ;

    var result = try e2e.runSource("unit_structure_if_expression.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "then\nelse\n");
}

test "match expressions can return structures without runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\item makeUnitStruct(message: string): UnitStruct = .{
        \\    field = printString(message),
        \\};
        \\val true_result: UnitStruct = match true {
        \\    true => makeUnitStruct("true"),
        \\    false => makeUnitStruct("not true"),
        \\};
        \\val false_result: UnitStruct = match false {
        \\    true => makeUnitStruct("not false"),
        \\    false => makeUnitStruct("false"),
        \\};
    ;

    var result = try e2e.runSource("unit_structure_match_expression.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "true\nfalse\n");
}

test "functions can have only erased parameters" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\item getValue(first: unit, second: UnitStruct): int = {
        \\    return 42;
        \\};
        \\printInt(getValue(
        \\    printString("first"),
        \\    UnitStruct { field = printString("second") }
        \\));
    ;

    var result = try e2e.runSource("only_erased_function_parameters.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "first\nsecond\n42\n");
}

test "structures can contain nested structures without runtime representation" {
    const source =
        \\item UnitStruct = structure {
        \\    field: unit;
        \\};
        \\item Outer = structure {
        \\    nested: UnitStruct;
        \\    value: int;
        \\};
        \\val outer: Outer = .{
        \\    nested = UnitStruct { field = printString("nested") },
        \\    value = 42,
        \\};
        \\val nested: UnitStruct = outer.nested;
        \\printInt(outer.value);
    ;

    var result = try e2e.runSource("nested_unit_structure_field.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "nested\n42\n");
}
