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
        .{ .severity = .@"error", .message = "declaration 'result' expects tagged union, found int" },
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
        .{ .severity = .@"error", .message = "instance method receiver expects int, found tagged union" },
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
