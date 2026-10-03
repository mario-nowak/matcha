const e2e = @import("helpers.zig");

test "unary not on int reports a semantic diagnostic" {
    const source =
        \\val bad = not 1;
    ;

    var result = try e2e.runSource("unary_not_on_int.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "unary operator 'not' is not supported for operand type int");
}

test "invalid compound assignment reports a semantic diagnostic" {
    const source =
        \\var flag = true;
        \\flag += 1;
    ;

    var result = try e2e.runSource("invalid_compound_assignment.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "binary operator '+' is not supported for left operand type boolean");
}

test "unit values compare equal and never unequal" {
    const source =
        \\printString(match {
        \\    unit == unit => "equal",
        \\    else => "not equal",
        \\});
        \\printString(match {
        \\    unit != unit => "unequal",
        \\    else => "not unequal",
        \\});
    ;

    var result = try e2e.runSource("unit_equality.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "equal\nnot unequal\n");
}

test "unit comparison evaluates both operands" {
    const source =
        \\val same = printInt(1) == printInt(2);
    ;

    var result = try e2e.runSource("unit_equality_side_effects.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "1\n2\n");
}

test "arrays compare by reference identity" {
    const source =
        \\val first = [1, 2, 3];
        \\val alias = first;
        \\val separate = [1, 2, 3];
        \\alias.append(4);
        \\printString(match {
        \\    first == alias => "alias equal",
        \\    else => "alias different",
        \\});
        \\printString(match {
        \\    first != separate => "separate different",
        \\    else => "separate equal",
        \\});
    ;

    var result = try e2e.runSource("array_equality.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "alias equal\nseparate different\n");
}
