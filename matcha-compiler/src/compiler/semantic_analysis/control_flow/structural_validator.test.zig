const std = @import("std");
const expect = @import("testing").expect;
const setupStructuralValidatorFixture = @import("testing").setupStructuralValidatorFixture;

test "StructuralValidator > validateProgram: accepts implicit member expressions" {
    const source = "val event = .PageLoad;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    try fixture.validator.validateProgram(&fixture.program);

    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "StructuralValidator > validateProgram: accepts return inside union functions" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = {
        \\        return "event";
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    try fixture.validator.validateProgram(&fixture.program);

    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "StructuralValidator > validateProgram: rejects continue when inside a union function but outside a loop" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = {
        \\        continue;
        \\        "event"
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    const result = fixture.validator.validateProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "continue is only allowed inside loops" },
    });
}
