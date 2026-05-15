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
