const e2e = @import("helpers.zig");

test "string concatenation, comparison, and length behave as expected" {
    const source =
        \\val greeting = "hello" + " world";
        \\val is_same = greeting == "hello world";
        \\val is_different = greeting != "other";
        \\printString(greeting);
        \\printInt(if is_same and is_different { 1 } else { 0 });
        \\printInt(greeting.length);
    ;

    var result = try e2e.runSource("strings_basic_operations.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "hello world\n1\n11\n");
}

test "string literal escapes print their decoded characters" {
    const source =
        \\printString("quote \" backslash \\ tab\tend\n");
    ;

    var result = try e2e.runSource("strings_escapes.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "quote \" backslash \\ tab\tend\n\n");
}

test "compound addition appends to a string variable" {
    const source =
        \\var text = "a";
        \\text += "b";
        \\printString(text);
    ;

    var result = try e2e.runSource("strings_compound_addition.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "ab\n");
}

test "string helpers trim split toInt and toString work together" {
    const source =
        \\val input = " 1,2 ";
        \\val trimmed = input.trim();
        \\val parts = trimmed.split(",");
        \\val sum = parts[0].toInt() + parts[1].toInt();
        \\printInt(sum);
        \\printString(sum.toString());
        \\printInt(trimmed.length);
    ;

    var result = try e2e.runSource("strings_helpers.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "3\n3\n3\n");
}

test "printString with int argument reports a semantic diagnostic" {
    const source =
        \\printString(42);
    ;

    var result = try e2e.runSource("print_string_with_int_argument.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "function argument expects string, found int");
}

test "slice returns the bytes between start and end" {
    const source =
        \\val text = "{\"key\": 1}";
        \\printString(text.slice(0, 1));
        \\printString(text.slice(1, 6));
        \\printInt(text.slice(3, 3).length);
    ;

    var result = try e2e.runSource("strings_slice.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "{\n\"key\"\n0\n");
}

test "slice reports a runtime error when the range is out of bounds" {
    const source =
        \\printString("abc".slice(2, 4));
    ;

    var result = try e2e.runSource("strings_slice_out_of_bounds.mt", source);
    defer result.deinit();

    try e2e.expectRuntimeError(&result, "runtime error: string slice [2, 4) is out of bounds for length 3");
}
