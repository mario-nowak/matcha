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
        \\item { printString } = import "builtin";
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
        \\item { printInt } = import "builtin";
        \\val same = printInt(1) == printInt(2);
    ;

    var result = try e2e.runSource("unit_equality_side_effects.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "1\n2\n");
}

test "arrays compare by reference identity" {
    const source =
        \\item { printString } = import "builtin";
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

test "compares a structure with an anonymous structure literal" {
    const source =
        \\item { printString } = import "builtin";
        \\item Point = structure { x: int; };
        \\val point = Point { x = 1 };
        \\printString(match {
        \\    point == .{ x = 1 } => "same",
        \\    else => "different",
        \\});
    ;

    var result = try e2e.runSource("structure_equality_anonymous_literal.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "different\n");
}

test "and skips the right operand when the left operand is false" {
    const source =
        \\item { printString } = import "builtin";
        \\item check(): boolean = {
        \\    printString("evaluated");
        \\    true
        \\};
        \\val both = false and check();
        \\printString("done");
    ;

    var result = try e2e.runSource("and_short_circuit.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "done\n");
}

test "or skips the right operand when the left operand is true" {
    const source =
        \\item { printString } = import "builtin";
        \\item check(): boolean = {
        \\    printString("evaluated");
        \\    true
        \\};
        \\val either = true or check();
        \\printString("done");
    ;

    var result = try e2e.runSource("or_short_circuit.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "done\n");
}

test "and guards an array index with a bounds check" {
    const source =
        \\item { printString } = import "builtin";
        \\val numbers = [1, 2];
        \\val index = 5;
        \\printString(if index < numbers.length and numbers[index] == 1 { "found" } else { "not found" });
    ;

    var result = try e2e.runSource("and_guards_index.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "not found\n");
}

test "evaluates an or nested in the right operand of an and" {
    const source =
        \\item { printString } = import "builtin";
        \\val left = true;
        \\printString(if left and (false or left) { "yes" } else { "no" });
    ;

    var result = try e2e.runSource("nested_and_or.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "yes\n");
}

pub const Matcha = struct {
    pub const run = struct {
        pub const integer_division = struct {
            test "divides integers toward zero" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\printInt(7 / 2);
                    \\printInt(-7 / 2);
                ;

                var result = try e2e.runSource("integer_division.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "3\n-3\n");
            }

            test "reports a division by zero with its location" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val divisor = 0;
                    \\printInt(10 / divisor);
                ;

                var result = try e2e.runSource("division_by_zero.mt", source);
                defer result.deinit();

                try e2e.expectRuntimeError(&result, "runtime error: division by zero\n  --> ");
                try e2e.expectContains(result.stderr, "/division_by_zero.mt:3:13\n");
            }

            test "reports an overflowing division with its location" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val dividend = -9223372036854775807 - 1;
                    \\val divisor = -1;
                    \\printInt(dividend / divisor);
                ;

                var result = try e2e.runSource("division_overflow.mt", source);
                defer result.deinit();

                try e2e.expectRuntimeError(&result, "runtime error: integer overflow in division\n  --> ");
                try e2e.expectContains(result.stderr, "/division_overflow.mt:4:19\n");
            }
        };

        pub const integer_remainder = struct {
            test "keeps the sign of the dividend" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\printInt(7 % 3);
                    \\printInt(-7 % 3);
                    \\printInt(7 % -3);
                ;

                var result = try e2e.runSource("integer_remainder.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "1\n-1\n1\n");
            }

            test "reports a remainder by zero with its location" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val divisor = 0;
                    \\printInt(10 % divisor);
                ;

                var result = try e2e.runSource("remainder_by_zero.mt", source);
                defer result.deinit();

                try e2e.expectRuntimeError(&result, "runtime error: division by zero\n  --> ");
                try e2e.expectContains(result.stderr, "/remainder_by_zero.mt:3:13\n");
            }

            test "returns zero for the smallest integer and a divisor of negative one" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\val dividend = -9223372036854775807 - 1;
                    \\val divisor = -1;
                    \\printInt(dividend % divisor);
                ;

                var result = try e2e.runSource("remainder_of_smallest_integer.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "0\n");
            }
        };

        pub const string_ordering = struct {
            test "orders strings byte by byte with a prefix first" {
                const source =
                    \\item { printInt } = import "builtin";
                    \\printInt(if "apple" < "banana" { 1 } else { 0 });
                    \\printInt(if "Zebra" < "apple" { 1 } else { 0 });
                    \\printInt(if "app" < "apple" { 1 } else { 0 });
                    \\printInt(if "b" <= "a" { 1 } else { 0 });
                    \\printInt(if "b" >= "b" { 1 } else { 0 });
                    \\printInt(if "b" > "a" { 1 } else { 0 });
                ;

                var result = try e2e.runSource("string_ordering.mt", source);
                defer result.deinit();

                try e2e.expectSuccessOutput(&result, "1\n1\n1\n0\n1\n1\n");
            }
        };
    };
};
