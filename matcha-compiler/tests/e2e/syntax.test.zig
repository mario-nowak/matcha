const e2e = @import("helpers.zig");

test "unterminated string literal reports a lexer diagnostic" {
    const source = "\"hello";

    var result = try e2e.runSource("unterminated_string_literal.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "unterminated string literal");
}

test "unrecognized character reports a lexer diagnostic" {
    const source =
        \\@
    ;

    var result = try e2e.runSource("unrecognized_character.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "unrecognized character");
}

test "missing declaration semicolon reports a parser diagnostic" {
    const source =
        \\val x = 1
        \\val y = 2;
    ;

    var result = try e2e.runSource("missing_declaration_semicolon.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "expected ';' after declaration");
}

test "malformed declaration array type reports a parser diagnostic" {
    const source =
        \\val xs: int[ = [1];
    ;

    var result = try e2e.runSource("malformed_declaration_array_type.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "expected ']' after array type suffix");
}

test "missing declaration type base reports a parser diagnostic" {
    const source =
        \\val xs: [] = [];
    ;

    var result = try e2e.runSource("missing_declaration_type_base.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "expected type annotation");
}

test "malformed function parameter array type reports a parser diagnostic" {
    const source =
        \\item f(xs: int[): int = 0;
    ;

    var result = try e2e.runSource("malformed_function_parameter_array_type.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "expected ']' after array type suffix");
}
