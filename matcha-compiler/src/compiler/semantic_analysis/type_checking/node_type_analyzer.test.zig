const std = @import("std");
const expect = @import("testing").expect;
const setupNodeTypeAnalyzerFixture = @import("testing").setupNodeTypeAnalyzerFixture;

test "NodeTypeAnalyzer > analyzeProgram: creates union types for encountered unions" {
    const source =
        \\item Result = union { None, Some: int };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const union_definition_node = resolved_program.program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    try expect(result.type_store.getType(union_type_id)).toMatch(.{ .Union = .{ .cases = .{
        .{ .type_id = result.type_store.unit_type_id },
        .{ .type_id = result.type_store.integer_type_id },
    } } });
}

test "NodeTypeAnalyzer > analyzeProgram: types a bare union case without a value as the underlying union type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.None;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: types a call on a union case with a unit value as the underlying union type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.None(unit);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id) catch |err| switch (err) {
        error.DiagnosticsEmitted => {
            std.debug.print("error: {s}\n", .{fixture.diagnostic_store.items()[0].message});
            return err;
        },
        else => unreachable,
    };

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: types a call on an implicit union case with a unit value as the underlying union type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .None(unit);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id) catch |err| switch (err) {
        error.DiagnosticsEmitted => {
            std.debug.print("error: {s}\n", .{fixture.diagnostic_store.items()[0].message});
            return err;
        },
        else => unreachable,
    };

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: types a call expression on a union case with a value as the underlying union type " {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Some(3);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: types a bare implicit union case without a value as the underlying union type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .None;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: types a call expression on a union case with a value as the underlying union type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .Some(3);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const resolved_program = fixture.resolved_program;
    const program = resolved_program.program;
    const union_definition_node = program.statements[0];
    const union_symbol_id = resolved_program.symbol_id_by_node_id.get(union_definition_node.id) orelse unreachable;
    const result_binding_node = program.statements[1];
    const result_symbol_id = resolved_program.symbol_id_by_node_id.get(result_binding_node.id) orelse unreachable;
    const union_case_node = result_binding_node.kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error diagnostic when using a union type as a value" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "'Result' is a type and cannot be used as a value" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error diagnostic when using a union case with a non-unit value outside of a call expression" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Some;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union constructors can only be called" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error diagnostic when implicitly using a union case with a non-unit value outside of a call expression" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .Some;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union constructors can only be called" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a non-unit value is called without a value " {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Some();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects 1 argument, found 0" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a non-unit value is implicitly called without a value " {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .Some();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects 1 argument, found 0" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a unit value is called without a value " {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.None();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects 1 argument, found 0" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a unit value is implicitly called without a value " {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .None();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects 1 argument, found 0" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a non-unit value is called with the wrong value type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Some("wrong");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects int, found string" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when a union case with a unit value is called with the wrong value type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.None("wrong");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects unit, found string" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when an implicit union case with a non-unit value is called with the wrong value type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .Some("wrong");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects int, found string" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram: reports an error when an implicit union case with a unit value is called with the wrong value type" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .None("wrong");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union construction expects unit, found string" },
    });
}
