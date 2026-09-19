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

test "NodeTypeAnalyzer > analyzeProgram: 1" {
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

test "NodeTypeAnalyzer > analyzeProgram: 2" {
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

test "NodeTypeAnalyzer > analyzeProgram: 3" {
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

// TODO: failing
test "NodeTypeAnalyzer > analyzeProgram: 4" {
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

    const result = fixture.node_type_analyzer.analyzeProgram(
        &fixture.resolved_program,
        fixture.exit_behavior_by_node_id,
    ) catch |analysis_error| switch (analysis_error) {
        error.DiagnosticsEmitted => {
            for (fixture.diagnostic_store.items()) |item| {
                std.debug.print("Encountered unexpected diagnostic during test: {s}\n", .{item.message});
            }
            return error.TestError;
        },
        else => unreachable,
    };

    const union_type_id = result.type_id_by_symbol_id.get(union_symbol_id) orelse unreachable;
    const result_type_id = result.type_id_by_symbol_id.get(result_symbol_id) orelse unreachable;
    try expect(result_type_id).toMatch(union_type_id);
    const union_case_node_type_id = result.type_id_by_node_id.get(union_case_node.id) orelse unreachable;
    try expect(union_case_node_type_id).toMatch(union_type_id);
}
