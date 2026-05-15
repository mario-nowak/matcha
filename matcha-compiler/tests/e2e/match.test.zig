const e2e = @import("helpers.zig");

test "subjectful and subjectless match expressions choose the right arm" {
    const source =
        \\val yes_or_no = match true {
        \\    true => "yes",
        \\    false => "no",
        \\};
        \\val sign = match {
        \\    3 > 0 => "positive",
        \\    else => "negative",
        \\};
        \\printString(yes_or_no);
        \\printString(sign);
    ;

    var result = try e2e.runSource("match_subjectful_and_subjectless.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "yes\npositive\n");
}

test "integer and string matches use else arms when needed" {
    const source =
        \\val level = match 2 {
        \\    1 => "one",
        \\    else => "other",
        \\};
        \\val tier = match "pro" {
        \\    "basic" => 1,
        \\    "pro" => 2,
        \\    else => 3,
        \\};
        \\printString(level);
        \\printInt(tier);
    ;

    var result = try e2e.runSource("match_integer_and_string.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "other\n2\n");
}

test "match expressions can be used directly as function bodies" {
    const source =
        \\item describe(flag: boolean): string = match flag {
        \\    true => "enabled",
        \\    false => "disabled",
        \\};
        \\printString(describe(true));
    ;

    var result = try e2e.runSource("match_function_body.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "enabled\n");
}

test "non-exhaustive boolean match reports a semantic diagnostic" {
    const source =
        \\val label = match true {
        \\    true => "yes",
        \\};
    ;

    var result = try e2e.runSource("non_exhaustive_boolean_match.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "match expression is not exhaustive");
}

test "duplicate boolean match arm reports a semantic diagnostic" {
    const source =
        \\val label = match true {
        \\    true => "yes",
        \\    true => "still yes",
        \\    false => "no",
        \\};
    ;

    var result = try e2e.runSource("duplicate_boolean_match_arm.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "duplicate 'true' match arm");
}

test "invalid integer match arm type reports a semantic diagnostic" {
    const source =
        \\val label = match 1 {
        \\    "two" => "two",
        \\    else => "other",
        \\};
    ;

    var result = try e2e.runSource("invalid_integer_match_arm_type.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "integer match arms must be integer expressions");
}

test "statement-position match with non-unit arms reports a semantic diagnostic" {
    const source =
        \\match true {
        \\    true => 1,
        \\    false => 0,
        \\};
    ;

    var result = try e2e.runSource("statement_position_match_non_unit.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "match expression used as a statement must evaluate to unit");
}
