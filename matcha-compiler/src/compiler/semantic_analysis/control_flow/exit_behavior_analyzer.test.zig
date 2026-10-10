const std = @import("std");
const expect = @import("testing").expect;
const setupExitBehaviorAnalyzerFixture = @import("testing").setupExitBehaviorAnalyzerFixture;

pub const ExitBehaviorAnalyzer = struct {
    pub const analyzeProgram = struct {
        pub const unions = struct {
            test "accepts implicit member expressions as function results" {
                const source = "item event(): WebEvent = .PageLoad;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const body = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression;

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result).toMatchMap(.{
                    .{ .key = body.id, .value = .falls_through_with_value },
                });
                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }

            test "accepts implicit member calls as function results" {
                const source = "item event(): WebEvent = .KeyPress(\"A\");";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const body = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression;
                const call = body.kind.call_expression;

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result).toMatchMap(.{
                    .{ .key = call.callee.id, .value = .falls_through_with_value },
                    .{ .key = call.arguments[0].id, .value = .falls_through_with_value },
                    .{ .key = body.id, .value = .falls_through_with_value },
                });
                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }

            test "accepts union functions that return a value" {
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
                const function = fixture.program.modules[0].statements[0].kind.item_definition.definition.@"union".function_definitions[0];
                const body = function.kind.item_definition.definition.function.body_expression;
                const return_statement = body.kind.block.statements[0];

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result).toMatchMap(.{
                    .{ .key = body.id, .value = .terminates },
                    .{ .key = return_statement.id, .value = .terminates },
                });
                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }

            test "rejects non-unit union functions when a return value is missing" {
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
        };

        pub const loops = struct {
            test "marks a loop as terminating when no leave targets it" {
                const source =
                    \\item spin(): unit = {
                    \\    loop {
                    \\        printInt(1);
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const loop = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression.kind.block.statements[0];

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(loop.id).?).toMatch(.terminates);
            }

            test "marks a loop as falling through without a value when a leave targets it" {
                const source =
                    \\item stop(): unit = {
                    \\    loop {
                    \\        leave;
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const loop = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression.kind.block.statements[0];

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(loop.id).?).toMatch(.falls_through_without_value);
            }

            test "marks a loop as terminating when only a nested loop has a leave" {
                const source =
                    \\item spin(): unit = {
                    \\    loop {
                    \\        while true {
                    \\            leave;
                    \\        }
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const loop = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression.kind.block.statements[0];

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(loop.id).?).toMatch(.terminates);
            }

            test "rejects a non-unit function when a leave exits a loop whose body returns" {
                const source =
                    \\item pick(stop: boolean): int = {
                    \\    loop {
                    \\        if stop {
                    \\            leave;
                    \\        }
                    \\        return 1;
                    \\    }
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
        };

        pub const match_expressions = struct {
            test "marks a match as falling through without a value when one arm leaves and another produces a value" {
                const source =
                    \\item search(): unit = {
                    \\    loop {
                    \\        val found = match 1 {
                    \\            1 => { leave; },
                    \\            else => 2,
                    \\        };
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const match_expression = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression.kind.block.statements[0].kind.loop.body_block.kind.block.statements[0].kind.binding_declaration.value;

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(match_expression.id).?).toMatch(.falls_through_without_value);
            }
        };

        pub const subjectless_match_expressions = struct {
            test "marks a match as falling through without a value when one arm leaves and another produces a value" {
                const source =
                    \\item search(): unit = {
                    \\    loop {
                    \\        val found = match {
                    \\            true => { leave; },
                    \\            else => 2,
                    \\        };
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const match_expression = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression.kind.block.statements[0].kind.loop.body_block.kind.block.statements[0].kind.binding_declaration.value;

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(match_expression.id).?).toMatch(.falls_through_without_value);
            }

            test "marks a match as terminating when an arm condition terminates" {
                const source =
                    \\item check(): int = match {
                    \\    { return 1; } => 2,
                    \\    else => 3,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupExitBehaviorAnalyzerFixture(&arena, source);
                const match_expression = fixture.program.modules[0].statements[0].kind.item_definition.definition.function.body_expression;

                const result = try fixture.analyzer.analyzeProgram(&fixture.program);

                try expect(result.get(match_expression.id).?).toMatch(.terminates);
            }
        };
    };
};
