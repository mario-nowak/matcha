const std = @import("std");
const expect = @import("testing").expect;
const setupNodeTypeAnalyzerFixture = @import("testing").setupNodeTypeAnalyzerFixture;

test "NodeTypeAnalyzer > analyzeProgram > unions: creates a union type with one payload type per case" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types a qualified unit case as the union when it is not called" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types a qualified unit case construction as the union" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types an implicit unit case construction as the union" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types a qualified payload case construction as the union" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types an implicit unit case as the union when it is not called" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types an implicit payload case construction as the union" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a union type when it is used as a value" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified payload case when it is not called" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit payload case when it is not called" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified payload case construction when it has no argument" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit payload case construction when it has no argument" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified unit case construction when it has no argument" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit unit case construction when it has no argument" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified payload case construction when the argument does not match the payload type" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified unit case construction when the argument is not unit" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit payload case construction when the argument does not match the payload type" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit unit case construction when the argument is not unit" {
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

test "NodeTypeAnalyzer > analyzeProgram > unions: types a qualified static function call as the return type when the function returns the union" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\    item fromString(value: string): Result = .Some(value.toInt());
        \\};
        \\val result = Result.fromString("3");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id) orelse unreachable;
    const result_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[1].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit member to a static function of the expected union" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\    item fromString(value: string): Result = .Some(value.toInt());
        \\};
        \\val result: Result = .fromString("3");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id) orelse unreachable;
    const result_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[1].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: types a qualified static function call as the return type when the function returns another type" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\    item getValue(): int = 1;
        \\};
        \\val result = Result.getValue();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const result_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[1].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(result.type_store.integer_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: reports a mismatch at the declaration when an implicit static function does not return the expected union" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\    item getValue(): int = 1;
        \\};
        \\val result: Result = .getValue();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "declaration 'result' expects Result, found int" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: types an instance method call on a constructed union as the method return type" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\
        \\    item getSelf(self: Result): Result = self;
        \\};
        \\val result = Result.Some(3).getSelf();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id) orelse unreachable;
    const result_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[1].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit case when it is the receiver of a method call" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\
        \\    item getSelf(self: Result): Result = self;
        \\};
        \\val result: Result = .Some(3).getSelf();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "cannot infer the type of an implicit member expression without an expected type" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an instance method call on a union when the receiver parameter has another type" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\
        \\    item getSelf(self: int): int = self;
        \\};
        \\val result = Result.Some(3).getSelf();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "instance method receiver expects int, found Result" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a member access on a union value when no member has that name" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\};
        \\val result = Result.Some(3).nonExistentFunction();
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "type 'Result' has no member named 'nonExistentFunction'" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the parameter type when it is an argument" {
    const source =
        \\item Result = union {
        \\    Some: int,
        \\};
        \\item asValue(result: Result): int = 1;
        \\var result = asValue(.Some(1));
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const result_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[2].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(result.type_store.integer_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: creates a constructor type per case that points back to its union and case index" {
    const source =
        \\item Result = union { None, Some: int };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const union_type = result.type_store.getType(union_type_id).Union;
    try expect(result.type_store.getType(union_type.cases[0].constructor_type_id)).toMatch(.{
        .UnionConstructor = .{ .union_type_id = union_type_id, .case_index = 0 },
    });
    try expect(result.type_store.getType(union_type.cases[1].constructor_type_id)).toMatch(.{
        .UnionConstructor = .{ .union_type_id = union_type_id, .case_index = 1 },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: types the callee of a payload case construction as the case constructor" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Some(3);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const callee_node = program.statements[1].kind.BindingDeclaration.value.kind.CallExpression.callee;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const union_type = result.type_store.getType(union_type_id).Union;
    const callee_type_id = result.type_id_by_node_id.get(callee_node.id) orelse unreachable;
    try expect(callee_type_id).toMatch(union_type.cases[1].constructor_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves a case payload that references the union itself" {
    const source =
        \\item List = union { Nil, Cons: List };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    try expect(result.type_store.getType(union_type_id)).toMatch(.{ .Union = .{ .cases = .{
        .{ .type_id = result.type_store.unit_type_id },
        .{ .type_id = union_type_id },
    } } });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves a case payload that references a structure defined later" {
    const source =
        \\item Event = union { Click: Point };
        \\item Point = structure { x: int; y: int; };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const structure_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[1].id) orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const structure_type_id = result.type_id_by_symbol_id.get(structure_symbol_id) orelse unreachable;
    try expect(result.type_store.getType(union_type_id)).toMatch(.{ .Union = .{ .cases = .{
        .{ .type_id = structure_type_id },
    } } });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the return type when it is a function body" {
    const source =
        \\item Result = union { None, Some: int };
        \\item make(): Result = .Some(1);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const body_node = program.statements[1].kind.ItemDefinition.definition.Function.body_expression;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const body_type_id = result.type_id_by_node_id.get(body_node.id) orelse unreachable;
    try expect(body_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the return type when it is a return value" {
    const source =
        \\item Result = union { None, Some: int };
        \\item make(): Result = { return .None; };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const body_node = program.statements[1].kind.ItemDefinition.definition.Function.body_expression;
    const return_value_node = body_node.kind.Block.statements[0].kind.ReturnStatement.value orelse unreachable;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const return_value_type_id = result.type_id_by_node_id.get(return_value_node.id) orelse unreachable;
    try expect(return_value_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves implicit cases against the expected type when they are if branches" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = if true { .Some(1) } else { .None };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const if_node = program.statements[1].kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const if_type_id = result.type_id_by_node_id.get(if_node.id) orelse unreachable;
    try expect(if_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the expected type when it is a block result" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = { .None };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const block_node = program.statements[1].kind.BindingDeclaration.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const block_type_id = result.type_id_by_node_id.get(block_node.id) orelse unreachable;
    try expect(block_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the binding type when it is assigned" {
    const source =
        \\item Result = union { None, Some: int };
        \\var result: Result = .None;
        \\result = .Some(2);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const union_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const assigned_value_node = program.statements[2].kind.AssignmentStatement.value;

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const assigned_value_type_id = result.type_id_by_node_id.get(assigned_value_node.id) orelse unreachable;
    try expect(assigned_value_type_id).toMatch(union_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an implicit case against the payload type when it is a construction argument" {
    const source =
        \\item Inner = union { None, Some: int };
        \\item Outer = union { Wrap: Inner };
        \\val outer = Outer.Wrap(.Some(1));
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const inner_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const outer_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[1].id) orelse unreachable;
    const outer_binding_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[2].id) orelse unreachable;
    const argument_node = &program.statements[2].kind.BindingDeclaration.value.kind.CallExpression.arguments[0];

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const inner_type_id = result.type_id_by_symbol_id.get(inner_symbol_id) orelse unreachable;
    const outer_type_id = result.type_id_by_symbol_id.get(outer_symbol_id) orelse unreachable;
    try expect(result.type_id_by_symbol_id.get(outer_binding_symbol_id) orelse unreachable).toMatch(outer_type_id);
    try expect(result.type_id_by_node_id.get(argument_node.id) orelse unreachable).toMatch(inner_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: resolves an anonymous structure literal against the payload type when it is a construction argument" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\item Event = union { Click: Point };
        \\val event: Event = .Click(.{ x = 1, y = 2 });
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
    const program = fixture.resolved_program.program;
    const structure_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(program.statements[0].id) orelse unreachable;
    const argument_node = &program.statements[2].kind.BindingDeclaration.value.kind.CallExpression.arguments[0];

    const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    const structure_type_id = result.type_id_by_symbol_id.get(structure_symbol_id) orelse unreachable;
    try expect(result.type_id_by_node_id.get(argument_node.id) orelse unreachable).toMatch(structure_type_id);
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit case when the expected type is not a union" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: int = .Some(1);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "implicit member expressions can only be used when the expected type is a union, found 'int'" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a qualified member when the union has no case or function with that name" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = Result.Nope;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "no function or case named 'Nope' exists on union type 'Result'" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit member when the union has no case or function with that name" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result: Result = .Nope;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "no function or case named 'Nope' exists on union type 'Result'" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects an implicit static function when it is not called" {
    const source =
        \\item Result = union {
        \\    None,
        \\    Some: int,
        \\    item fromString(value: string): Result = .Some(value.toInt());
        \\};
        \\val result: Result = .fromString;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "functions can only be called; function values are not supported yet" },
    });
}

test "NodeTypeAnalyzer > analyzeProgram > unions: rejects a payload case when it reaches the callee through an if branch" {
    const source =
        \\item Result = union { None, Some: int };
        \\val result = (if true { Result.Some } else { Result.Some })(1);
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
