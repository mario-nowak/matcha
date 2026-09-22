const e2e = @import("helpers.zig");

test "built-in printInt prints integers" {
    const source =
        \\printInt(42);
    ;

    var result = try e2e.runSource("print_int.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "42\n");
}

test "expression-bodied functions can call each other" {
    const source =
        \\item identity(value: int): int = value;
        \\item double(value: int): int = identity(value) * 2;
        \\printInt(double(21));
    ;

    var result = try e2e.runSource("functions_expression_bodies.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "42\n");
}

test "block-bodied functions can return computed values" {
    const source =
        \\item sumTo(limit: int): int = {
        \\    var i = 0;
        \\    var sum = 0;
        \\    while i <= limit : i += 1 {
        \\        sum += i;
        \\    }
        \\    return sum;
        \\};
        \\printInt(sumTo(4));
    ;

    var result = try e2e.runSource("functions_block_body.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "10\n");
}

test "function fallthrough reports an exit-behavior diagnostic" {
    const source =
        \\item f(): int = if true { 1 } else { val x = 1; };
    ;

    var result = try e2e.runSource("function_fallthrough.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "not all control-flow paths in this function return a value");
}

test "function used as a value reports a diagnostic" {
    const source =
        \\item f(): int = 1;
        \\val x = f;
    ;

    var result = try e2e.runSource("function_as_value.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "functions can only be called; function values are not supported yet");
}

test "function selected by an if-expression cannot be called" {
    const source =
        \\item f(): int = 1;
        \\item g(): int = 2;
        \\printInt((if true { f } else { g })());
    ;

    var result = try e2e.runSource("function_from_if_expression.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "functions can only be called; function values are not supported yet");
}

test "type name used as a value reports a diagnostic" {
    const source =
        \\item SomeStructure = structure {
        \\    field: int;
        \\};
        \\val x = SomeStructure;
    ;

    var result = try e2e.runSource("type_name_as_value.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "'SomeStructure' is a type and cannot be used as a value");
}
