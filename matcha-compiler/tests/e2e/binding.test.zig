const e2e = @import("helpers.zig");

test "declaration type mismatch reports a semantic diagnostic" {
    const source =
        \\val x: int = true;
    ;

    var result = try e2e.runSource("declaration_type_mismatch.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "declaration 'x' expects int, found boolean");
}

test "rebinding immutable binding reports a semantic diagnostic" {
    const source =
        \\val answer = 1;
        \\answer = 2;
    ;

    var result = try e2e.runSource("rebinding_immutable_binding.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "cannot assign to immutable binding 'answer'");
}
