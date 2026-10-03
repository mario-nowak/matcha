const e2e = @import("helpers.zig");

pub const Matcha = struct {
    pub const run = struct {
        pub const unions = struct {
            pub const arms = struct {
                test "runs the arm of the constructed case and binds its payload" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(4);
                        \\printInt(match offset {
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value * 10,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_payload_binding.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "4\n");
                }

                test "runs the last arm when no earlier arm matches" {
                    const source =
                        \\item Offset = union { None, Horizontal: int, Vertical: int };
                        \\val offset = Offset.Vertical(-3);
                        \\printInt(match offset {
                        \\    .None => 0,
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value * 10,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_last_arm.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "-30\n");
                }

                test "runs the arm of a payloadless case" {
                    const source =
                        \\item Maybe = union { None, Some: int };
                        \\val maybe = Maybe.None;
                        \\printInt(match maybe {
                        \\    .None => 0,
                        \\    .Some(value) => value,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_payloadless_case.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "0\n");
                }

                test "runs the matching arm when the arms are in a different order than the cases" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(5);
                        \\printInt(match offset {
                        \\    .Vertical(value) => value * 10,
                        \\    .Horizontal(value) => value * 100,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_arm_order.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "500\n");
                }

                test "matches qualified case patterns like implicit case patterns" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Vertical(7);
                        \\printInt(match offset {
                        \\    Offset.Horizontal(value) => value * 10,
                        \\    Offset.Vertical(value) => value,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_qualified_patterns.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "7\n");
                }

                test "ignores the payload when a case pattern has no binding" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Vertical(7);
                        \\printInt(match offset {
                        \\    .Horizontal => 1,
                        \\    .Vertical => 2,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_ignored_payload.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "2\n");
                }

                test "runs the else arm when no case arm matches" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Vertical(7);
                        \\printInt(match offset {
                        \\    .Horizontal(value) => value,
                        \\    else => -1,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_else_arm.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "-1\n");
                }

                test "runs only the side effects of the matched arm when the match is a statement" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset = Offset.Horizontal(4);
                        \\match offset {
                        \\    .Horizontal(value) => printInt(value),
                        \\    .Vertical(value) => printInt(value * 10),
                        \\};
                    ;

                    var result = try e2e.runSource("unions_statement_match.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "4\n");
                }

                test "returns from the function when the matched arm returns" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\item horizontalOrZero(offset: Offset): int = {
                        \\    match offset {
                        \\        .Horizontal(value) => {
                        \\            return value;
                        \\        },
                        \\        else => {
                        \\            return 0;
                        \\        },
                        \\    };
                        \\};
                        \\printInt(horizontalOrZero(Offset.Horizontal(4)));
                        \\printInt(horizontalOrZero(Offset.Vertical(1)));
                    ;

                    var result = try e2e.runSource("unions_early_return.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "4\n0\n");
                }
            };

            pub const implicit_construction = struct {
                test "constructs a payload case from the declared type" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\val offset: Offset = .Horizontal(4);
                        \\printInt(match offset {
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value * 10,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_implicit_payload_case.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "4\n");
                }

                test "constructs a payloadless case from the declared type" {
                    const source =
                        \\item Maybe = union { None, Some: int };
                        \\val maybe: Maybe = .None;
                        \\printInt(match maybe {
                        \\    .None => 0,
                        \\    .Some(value) => value,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_implicit_payloadless_case.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "0\n");
                }
            };

            pub const values = struct {
                test "passes a union to a function" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\item length(offset: Offset): int = match offset {
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value * 10,
                        \\};
                        \\printInt(length(Offset.Vertical(4)));
                    ;

                    var result = try e2e.runSource("unions_function_argument.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "40\n");
                }

                test "returns a union from a function" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\item rotate(offset: Offset): Offset = match offset {
                        \\    .Horizontal(value) => Offset.Vertical(value),
                        \\    .Vertical(value) => Offset.Horizontal(value),
                        \\};
                        \\printInt(match rotate(Offset.Horizontal(4)) {
                        \\    .Horizontal(value) => value,
                        \\    .Vertical(value) => value * 10,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_function_result.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "40\n");
                }

                test "reassigns a mutable union binding to a different case" {
                    const source =
                        \\item Maybe = union { None, Some: int };
                        \\var maybe = Maybe.None;
                        \\maybe = Maybe.Some(9);
                        \\printInt(match maybe {
                        \\    .None => 0,
                        \\    .Some(value) => value,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_reassignment.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "9\n");
                }

                test "stores unions in an array" {
                    const source =
                        \\item Maybe = union { None, Some: int };
                        \\val maybes: Maybe[] = [.Some(1), .None, .Some(20)];
                        \\var sum = 0;
                        \\for maybe in maybes {
                        \\    sum += match maybe {
                        \\        .None => 300,
                        \\        .Some(value) => value,
                        \\    };
                        \\}
                        \\printInt(sum);
                    ;

                    var result = try e2e.runSource("unions_array.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "321\n");
                }

                test "stores a union in a structure field" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\item Move = structure {
                        \\    offset: Offset;
                        \\};
                        \\val move = Move { offset = Offset.Vertical(6) };
                        \\printInt(match move.offset {
                        \\    .Horizontal(value) => value * 10,
                        \\    .Vertical(value) => value,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_structure_field.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "6\n");
                }
            };

            pub const payloads = struct {
                test "binds a string payload" {
                    const source =
                        \\item Message = union { Empty, Text: string };
                        \\val message = Message.Text("hello");
                        \\printString(match message {
                        \\    .Empty => "",
                        \\    .Text(text) => text,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_string_payload.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "hello\n");
                }

                test "binds a structure payload" {
                    const source =
                        \\item Point = structure {
                        \\    x: int;
                        \\    y: int;
                        \\};
                        \\item Shape = union { Empty, Dot: Point };
                        \\val shape = Shape.Dot(Point { x = 3, y = 4 });
                        \\printInt(match shape {
                        \\    .Empty => 0,
                        \\    .Dot(point) => point.x + point.y,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_structure_payload.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "7\n");
                }

                test "binds a union payload" {
                    const source =
                        \\item Offset = union { Horizontal: int, Vertical: int };
                        \\item Step = union { Stay, Move: Offset };
                        \\val step = Step.Move(Offset.Vertical(8));
                        \\printInt(match step {
                        \\    .Stay => 0,
                        \\    .Move(offset) => match offset {
                        \\        .Horizontal(value) => value * 10,
                        \\        .Vertical(value) => value,
                        \\    },
                        \\});
                    ;

                    var result = try e2e.runSource("unions_union_payload.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "8\n");
                }

                test "binds a unit payload" {
                    const source =
                        \\item Signal = union { Off, On: unit };
                        \\val signal = Signal.On(unit);
                        \\printInt(match signal {
                        \\    .Off => 0,
                        \\    .On(nothing) => 1,
                        \\});
                    ;

                    var result = try e2e.runSource("unions_unit_payload.mt", source);
                    defer result.deinit();

                    try e2e.expectSuccessOutput(&result, "1\n");
                }
            };
        };
    };
};
