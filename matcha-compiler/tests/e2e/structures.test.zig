const e2e = @import("helpers.zig");

test "structure construction member access and type functions work together" {
    const source =
        \\item Point = structure {
        \\    x: int;
        \\    y: int;
        \\
        \\    item origin(): Point = .{
        \\        x = 0,
        \\        y = 0,
        \\    };
        \\
        \\    item movedBy(self: Point, other: Point): Point = .{
        \\        x = self.x + other.x,
        \\        y = self.y + other.y,
        \\    };
        \\};
        \\val point = Point.origin().movedBy(Point { x = 3, y = 4 });
        \\printInt(point.x);
        \\printInt(point.y);
    ;

    var result = try e2e.runSource("structures_type_functions.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "3\n4\n");
}

test "anonymous structure literals contextual typing and instance methods work together" {
    const source =
        \\item Point = structure {
        \\    x: int;
        \\    y: int;
        \\
        \\    item invert(self: Point): unit = {
        \\        self.x *= -1;
        \\        self.y *= -1;
        \\    };
        \\};
        \\var point: Point = .{ x = 3, y = 4 };
        \\point.invert();
        \\printInt(point.x);
        \\printInt(point.y);
    ;

    var result = try e2e.runSource("structures_instance_methods.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "-3\n-4\n");
}

test "invalid structure member access reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\val z = point.z;
    ;

    var result = try e2e.runSource("invalid_structure_member_access.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "type 'Point' has no member named 'z'");
}

test "anonymous structure literal without contextual type reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = .{ x = 1, y = 2 };
    ;

    var result = try e2e.runSource("anonymous_structure_literal_without_context.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "cannot infer the type of an anonymous structure literal without a contextual type");
}

test "undefined structure reports a semantic diagnostic" {
    const source =
        \\val point = Point { x = 1, y = 2 };
    ;

    var result = try e2e.runSource("undefined_structure.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "undefined structure 'Point'");
}

test "missing structure field reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1 };
    ;

    var result = try e2e.runSource("missing_structure_field.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "missing field 'y' in construction of 'Point'");
}

test "duplicate structure field reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, x = 2, y = 3 };
    ;

    var result = try e2e.runSource("duplicate_structure_field.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "duplicate field 'x' in structure construction");
}

test "unknown structure field reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, z = 2, y = 3 };
    ;

    var result = try e2e.runSource("unknown_structure_field.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "field 'z' does not exist on structure 'Point'");
}

test "wrong structure field type reports a semantic diagnostic" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = true, y = 2 };
    ;

    var result = try e2e.runSource("wrong_structure_field_type.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "field 'x' on structure 'Point' expects int, found boolean");
}

test "structure field and method name collision reports a semantic diagnostic" {
    const source =
        \\item User = structure {
        \\    name: string;
        \\    item name(): string = "duplicate";
        \\};
    ;

    var result = try e2e.runSource("structure_field_method_collision.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "structure member 'name' is already declared in 'User'");
}

test "duplicate structure method names report a semantic diagnostic" {
    const source =
        \\item User = structure {
        \\    id: int;
        \\    item format(): string = "a";
        \\    item format(): string = "b";
        \\};
    ;

    var result = try e2e.runSource("duplicate_structure_method_names.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "structure member 'format' is already declared in 'User'");
}
