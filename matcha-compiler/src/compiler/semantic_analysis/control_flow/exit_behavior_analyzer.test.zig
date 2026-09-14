const std = @import("std");
const expect = @import("testing").expect;
const setupExitBehaviorAnalyzerFixture = @import("testing").setupExitBehaviorAnalyzerFixture;

test "ExitBehaviorAnalyzer > analyzeProgram: accepts implicit member expressions as function results" {
    const source = "item event(): WebEvent = .PageLoad;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
    const body = fixture.program.statements[0].kind.ItemDefinition.definition.Function.body_expression;

    const result = try fixture.analyzer.analyzeProgram(&fixture.program);

    try expect(result).toMatchMap(.{
        .{ .key = body.id, .value = .FallsThroughWithValue },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "ExitBehaviorAnalyzer > analyzeProgram: accepts implicit member calls as function results" {
    const source = "item event(): WebEvent = .KeyPress(\"A\");";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
    const body = fixture.program.statements[0].kind.ItemDefinition.definition.Function.body_expression;
    const call = body.kind.CallExpression;

    const result = try fixture.analyzer.analyzeProgram(&fixture.program);

    try expect(result).toMatchMap(.{
        .{ .key = call.callee.id, .value = .FallsThroughWithValue },
        .{ .key = call.arguments[0].id, .value = .FallsThroughWithValue },
        .{ .key = body.id, .value = .FallsThroughWithValue },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "ExitBehaviorAnalyzer > analyzeProgram: accepts union functions that return a value" {
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
    const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
    const function = fixture.program.statements[0].kind.ItemDefinition.definition.Union.function_definitions[0];
    const body = function.kind.ItemDefinition.definition.Function.body_expression;
    const return_statement = body.kind.Block.statements[0];

    const result = try fixture.analyzer.analyzeProgram(&fixture.program);

    try expect(result).toMatchMap(.{
        .{ .key = body.id, .value = .Terminates },
        .{ .key = return_statement.id, .value = .Terminates },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "ExitBehaviorAnalyzer > analyzeProgram: rejects non-unit union functions when a return value is missing" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = {
        \\        "event";
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);

    const result = fixture.analyzer.analyzeProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "not all control-flow paths in this function return a value" },
    });
}
