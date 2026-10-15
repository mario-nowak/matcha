const e2e = @import("helpers.zig");

test "string concatenation, comparison, and length behave as expected" {
    const source =
        \\item { printString, printInt } = import "builtin";
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
        \\item { printString } = import "builtin";
        \\printString("quote \" backslash \\ tab\tend\n");
    ;

    var result = try e2e.runSource("strings_escapes.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "quote \" backslash \\ tab\tend\n\n");
}

test "compound addition appends to a string variable" {
    const source =
        \\item { printString } = import "builtin";
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
        \\item { printInt, printString } = import "builtin";
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
        \\item { printString } = import "builtin";
        \\printString(42);
    ;

    var result = try e2e.runSource("print_string_with_int_argument.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "function argument expects string, found int");
}

test "slice returns the bytes between start and end" {
    const source =
        \\item { printString, printInt } = import "builtin";
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
        \\item { printString } = import "builtin";
        \\printString("abc".slice(2, 4));
    ;

    var result = try e2e.runSource("strings_slice_out_of_bounds.mt", source);
    defer result.deinit();

    try e2e.expectRuntimeError(&result, "runtime error: string slice [2, 4) is out of bounds for length 3");
}

pub const Matcha = struct {
    pub const run = struct {
        pub const string_bytes = struct {
            test "returns the bytes of a string, not its characters" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val text = "Ab";
                    \\printInt(text.getByteAt(0));
                    \\printInt(text.getByteAt(1));
                    \\printInt("é".getByteAt(0));
                ;

                var result = try e2e.runSource("string_bytes.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "65\n98\n195\n");
            }

            test "reports an index out of bounds with its location" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val text = "abc";
                    \\printInt(text.getByteAt(3));
                ;

                var result = try e2e.runSource("string_byte_out_of_bounds.mt", source);
                defer result.deinit();

                try e2e.expectRuntimeError(&result, "runtime error: string index out of bounds\n  --> ");
                try e2e.expectContains(result.stderr, "/string_byte_out_of_bounds.mt:3:15\n");
                try e2e.expectContains(result.stderr, "index 3 is out of bounds for length 3");
            }
        };

        pub const string_joining = struct {
            test "puts the separator only between elements" {
                const source =
                    \\item { printString } = import "builtin";
                    \\val several: string[] = ["a", "b", "c"];
                    \\val single: string[] = ["a"];
                    \\val none: string[] = [];
                    \\printString(several.join(", "));
                    \\printString(single.join(", "));
                    \\printString(none.join(", "));
                ;

                var result = try e2e.runSource("string_joining.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "a, b, c\na\n\n");
            }
        };
    };
};
