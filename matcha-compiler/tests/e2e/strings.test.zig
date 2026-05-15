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
