const e2e = @import("helpers.zig");

test "if statements, if expressions, and block results produce the expected values" {
    const source =
        \\var confirmed = 0;
        \\if true {
        \\    confirmed = 1;
        \\}
        \\val score = if confirmed == 1 { 2 } else { 0 };
        \\val total = {
        \\    val left = 3;
        \\    val right = 4;
        \\    left + right
        \\};
        \\printInt(confirmed);
        \\printInt(score);
        \\printInt(total);
    ;

    var result = try e2e.runSource("control_flow_if_and_block.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "1\n2\n7\n");
}

test "while loops and headless loops update values until leave" {
    const source =
        \\var i = 0;
        \\var sum = 0;
        \\while i < 4 : i += 1 {
        \\    sum += i;
        \\}
        \\loop {
        \\    if sum >= 10 {
        \\        leave;
        \\    }
        \\    sum += 1;
        \\}
        \\printInt(sum);
    ;

    var result = try e2e.runSource("control_flow_loops.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "10\n");
}

test "one-branch if without braces reports a parser diagnostic" {
    const source =
        \\if true printInt(1);
    ;

    var result = try e2e.runSource("if_without_braces.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "expected '{' after if condition");
}

test "non-boolean if condition reports a semantic diagnostic" {
    const source =
        \\if 1 { val x = 1; }
    ;

    var result = try e2e.runSource("non_boolean_if_condition.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "if condition must be boolean, found int");
}

test "non-boolean while condition reports a semantic diagnostic" {
    const source =
        \\while 1 {
        \\    leave;
        \\}
    ;

    var result = try e2e.runSource("non_boolean_while_condition.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "while condition must be boolean, found int");
}

test "mismatched if-expression branches report a semantic diagnostic" {
    const source =
        \\val value = if true { 1 } else { false };
    ;

    var result = try e2e.runSource("mismatched_if_expression_branches.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "if-expression branches must have the same type, found then: int, else: boolean");
}

test "non-unit if-expression statement reports a semantic diagnostic" {
    const source =
        \\if true { 1 } else { 2 };
    ;

    var result = try e2e.runSource("non_unit_if_expression_statement.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "block cannot have a trailing expression in statement context");
}

test "continue outside loops reports a structural diagnostic" {
    const source =
        \\if true {
        \\    continue;
        \\}
    ;

    var result = try e2e.runSource("continue_outside_loops.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "continue is only allowed inside loops");
}

test "leave outside loops reports a structural diagnostic" {
    const source =
        \\if true {
        \\    leave;
        \\}
    ;

    var result = try e2e.runSource("leave_outside_loops.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "leave is only allowed inside loops");
}
