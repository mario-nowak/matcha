const e2e = @import("helpers.zig");

test "arrays support append indexing length and for-in iteration" {
    const source =
        \\val numbers = [1, 2, 3];
        \\numbers.append(4);
        \\numbers[0] = 10;
        \\var sum = 0;
        \\for number in numbers {
        \\    sum += number;
        \\}
        \\printInt(numbers.length);
        \\printInt(sum);
    ;

    var result = try e2e.runSource("arrays_operations.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "4\n19\n");
}

test "non-array for-in iterable reports a semantic diagnostic" {
    const source =
        \\for value in 1 {
        \\    printInt(value);
        \\}
    ;

    var result = try e2e.runSource("non_array_for_in_iterable.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "for-in iterable must be an array, found int");
}

test "assignment to immutable for-in item reports a semantic diagnostic" {
    const source =
        \\val numbers = [1, 2, 3];
        \\for number in numbers {
        \\    number = 4;
        \\}
    ;

    var result = try e2e.runSource("assignment_to_immutable_for_in_item.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "cannot assign to immutable binding 'number'");
}

test "assigning to array length reports a semantic diagnostic" {
    const source =
        \\var numbers = [1, 2, 3];
        \\numbers.length = 4;
    ;

    var result = try e2e.runSource("assigning_to_array_length.mt", source);
    defer result.deinit();

    try e2e.expectCompileDiagnostic(&result, "cannot assign to read-only array member 'length'");
}
