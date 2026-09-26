const std = @import("std");
const expect = @import("testing").expect;
const setupNodeTypeAnalyzerFixture = @import("testing").setupNodeTypeAnalyzerFixture;

pub const NodeTypeAnalyzer = struct {
    pub const analyzeProgram = struct {
        pub const unions = struct {
            pub const definitions = struct {
                test "creates a union type with one payload type per case" {
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

                test "creates a constructor type per case that points back to its union and case index" {
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

                test "resolves a case payload that references the union itself" {
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

                test "resolves a case payload that references a structure defined later" {
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
            };

            pub const qualified_cases = struct {
                test "types a unit case as the union when it is not called" {
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

                test "types a unit case construction as the union" {
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

                test "types a payload case construction as the union" {
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

                test "rejects a union type when it is used as a value" {
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

                test "rejects a payload case when it is not called" {
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

                test "rejects a payload case construction when it has no argument" {
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

                test "rejects a unit case construction when it has no argument" {
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

                test "rejects a payload case construction when the argument does not match the payload type" {
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

                test "rejects a unit case construction when the argument is not unit" {
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

                test "types the callee of a payload case construction as the case constructor" {
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

                test "rejects a member when the union has no case or function with that name" {
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

                test "rejects a payload case when it reaches the callee through an if branch" {
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
            };

            pub const implicit_cases = struct {
                test "types a unit case construction as the union" {
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

                test "types a unit case as the union when it is not called" {
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

                test "types a payload case construction as the union" {
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

                test "rejects a payload case when it is not called" {
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

                test "rejects a payload case construction when it has no argument" {
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

                test "rejects a unit case construction when it has no argument" {
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

                test "rejects a payload case construction when the argument does not match the payload type" {
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

                test "rejects a unit case construction when the argument is not unit" {
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

                test "rejects a member when the union has no case or function with that name" {
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
            };

            pub const expected_types = struct {
                test "resolves an implicit case against the parameter type when it is an argument" {
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

                test "resolves an implicit case against the return type when it is a function body" {
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

                test "resolves an implicit case against the return type when it is a return value" {
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

                test "resolves implicit cases against the expected type when they are if branches" {
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

                test "resolves an implicit case against the expected type when it is a block result" {
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

                test "resolves an implicit case against the binding type when it is assigned" {
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

                test "resolves an implicit case against the payload type when it is a construction argument" {
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

                test "resolves an anonymous structure literal against the payload type when it is a construction argument" {
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

                test "rejects an implicit case when the expected type is not a union" {
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
            };

            pub const static_functions = struct {
                test "types a qualified static function call as the return type when the function returns the union" {
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

                test "resolves an implicit member to a static function of the expected union" {
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

                test "types a qualified static function call as the return type when the function returns another type" {
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

                test "reports a mismatch at the declaration when an implicit static function does not return the expected union" {
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

                test "rejects an implicit static function when it is not called" {
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
            };

            pub const instance_methods = struct {
                test "types an instance method call on a constructed union as the method return type" {
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

                test "rejects an implicit case when it is the receiver of a method call" {
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

                test "rejects an instance method call on a union when the receiver parameter has another type" {
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

                test "rejects a member access on a union value when no member has that name" {
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
            };
        };

        pub const literals = struct {
            test "types the unit literal as unit" {
                const source =
                    \\val value = unit;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const unit_literal = fixture.resolved_program.program.statements[0].kind.BindingDeclaration.value;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_node_id.get(unit_literal.id).?)).toMatch(.Unit);
            }
        };

        pub const functions = struct {
            test "types a parameter reference in a function body as the parameter type" {
                const source =
                    \\item identity(value: int): int = value;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const body_expression = fixture.resolved_program.program.statements[0].kind.ItemDefinition.definition.Function.body_expression;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_node_id.get(body_expression.id).?)).toMatch(.Integer);
            }

            test "types array parameters and returns in a function signature as arrays" {
                const source =
                    \\item identity(values: int[]): int[] = values;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const function_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_symbol_id.get(function_symbol_id).?)).toMatch(.{ .Function = .{ .parameter_type_ids = .{result.type_store.getArrayType(result.type_store.integer_type_id).?}, .return_type_id = result.type_store.getArrayType(result.type_store.integer_type_id).? } });
            }
        };

        pub const match_expressions = struct {
            test "rejects a duplicate negative integer arm" {
                const source =
                    \\val name = match 0 {
                    \\    -1 => "first",
                    \\    -1 => "second",
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "duplicate integer match arm for value -1" },
                });
            }

            test "rejects a case pattern when the subject is an integer" {
                const source =
                    \\val name = match 0 {
                    \\    .Some(value) => "some",
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "integer match arms must use integer literals" },
                });
            }

            test "rejects a unit subject" {
                const source =
                    \\val name = match unit {
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match subject must be boolean, integer, or string, found unit" },
                });
            }

            test "rejects an integer pattern when the subject is a boolean" {
                const source =
                    \\val name = match true {
                    \\    1 => "one",
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "boolean match arms must use boolean literals" },
                });
            }

            test "rejects an integer pattern when the subject is a string" {
                const source =
                    \\val name = match "pro" {
                    \\    1 => "one",
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "string match arms must use string literals" },
                });
            }

            test "rejects arms that produce different types" {
                const source =
                    \\val name = match 1 {
                    \\    1 => "one",
                    \\    2 => 2,
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match arms must all produce the same type, expected string, found int" },
                });
            }

            test "rejects an else arm that produces a different type than the arms" {
                const source =
                    \\val name = match 1 {
                    \\    1 => "one",
                    \\    else => 2,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match else arm must produce the same type as other arms, expected string, found int" },
                });
            }

            test "rejects a match without an else arm when the patterns do not cover every value" {
                const source =
                    \\val name = match 1 {
                    \\    1 => "one",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match expression is not exhaustive" },
                });
            }
        };

        pub const subjectless_match_expressions = struct {
            test "rejects an integer condition" {
                const source =
                    \\val name = match {
                    \\    1 => "one",
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "subjectless match arm condition must be boolean, found int" },
                });
            }

            test "rejects arms that produce different types" {
                const source =
                    \\val name = match {
                    \\    true => "one",
                    \\    false => 2,
                    \\    else => "other",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match arms must all produce the same type, expected string, found int" },
                });
            }

            test "rejects an else arm that produces a different type than the arms" {
                const source =
                    \\val name = match {
                    \\    true => "one",
                    \\    else => 2,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match else arm must produce the same type as other arms, expected string, found int" },
                });
            }

            test "rejects a match without an else arm" {
                const source =
                    \\val name = match {
                    \\    true => "one",
                    \\    false => "two",
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "match expression is not exhaustive" },
                });
            }
        };

        pub const structures = struct {
            test "records a field access with its field index" {
                const source =
                    \\item Point = structure { x: int; y: int; };
                    \\val point = Point { x = 1, y = 2 };
                    \\val y = point.y;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const member_expression = fixture.resolved_program.program.statements[2].kind.BindingDeclaration.value;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.member_access_by_node_id.get(member_expression.id).?).toMatch(.{ .StructureInstanceFieldAccess = .{ .field_index = 1 } });
            }

            test "types a field access as the field type" {
                const source =
                    \\item Named = structure { name: string; };
                    \\val named = Named { name = "a" };
                    \\val name = named.name;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const member_expression = fixture.resolved_program.program.statements[2].kind.BindingDeclaration.value;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_node_id.get(member_expression.id).?)).toMatch(.String);
            }

            test "records a type function access with its structure and function" {
                const source =
                    \\item Point = structure {
                    \\    x: int;
                    \\
                    \\    item origin(): Point = Point { x = 0 };
                    \\};
                    \\val point = Point.origin();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const point_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;
                const origin_symbol_id = fixture.resolved_program.symbol_table.getSymbol(point_symbol_id).kind.Structure.function_symbol_ids[0];
                const callee = fixture.resolved_program.program.statements[1].kind.BindingDeclaration.value.kind.CallExpression.callee;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.member_access_by_node_id.get(callee.id).?).toMatch(.{ .StructureTypeFunctionAccess = .{ .structure_symbol_id = point_symbol_id, .function_symbol_id = origin_symbol_id } });
            }

            test "records a method access with its structure and function" {
                const source =
                    \\item Point = structure {
                    \\    x: int;
                    \\
                    \\    item moved(self: Point): Point = self;
                    \\};
                    \\val point = Point { x = 1 };
                    \\val moved = point.moved();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const point_symbol_id = fixture.resolved_program.symbol_id_by_node_id.get(fixture.resolved_program.program.statements[0].id).?;
                const moved_symbol_id = fixture.resolved_program.symbol_table.getSymbol(point_symbol_id).kind.Structure.function_symbol_ids[0];
                const callee = fixture.resolved_program.program.statements[2].kind.BindingDeclaration.value.kind.CallExpression.callee;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.member_access_by_node_id.get(callee.id).?).toMatch(.{ .StructureInstanceMethodAccess = .{ .structure_symbol_id = point_symbol_id, .function_symbol_id = moved_symbol_id } });
            }

            test "types a method callee without its receiver parameter" {
                const source =
                    \\item Point = structure {
                    \\    x: int;
                    \\
                    \\    item shifted(self: Point, offset: int): Point = self;
                    \\};
                    \\val point = Point { x = 1 };
                    \\val shifted = point.shifted(1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const callee = fixture.resolved_program.program.statements[2].kind.BindingDeclaration.value.kind.CallExpression.callee;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_node_id.get(callee.id).?)).toMatch(.{ .Function = .{ .parameter_type_ids = .{result.type_store.integer_type_id} } });
            }
        };

        pub const arrays = struct {
            test "records the length of an array as an array field access" {
                const source =
                    \\val numbers = [1, 2];
                    \\val length = numbers.length;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const member_expression = fixture.resolved_program.program.statements[1].kind.BindingDeclaration.value;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.member_access_by_node_id.get(member_expression.id).?).toMatch(.{ .ArrayInstanceFieldAccess = .Length });
            }

            test "types the length of an array as an integer" {
                const source =
                    \\val numbers = [1, 2];
                    \\val length = numbers.length;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const member_expression = fixture.resolved_program.program.statements[1].kind.BindingDeclaration.value;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.type_store.getType(result.type_id_by_node_id.get(member_expression.id).?)).toMatch(.Integer);
            }

            test "records append on an array as an array method access" {
                const source =
                    \\val numbers = [1];
                    \\numbers.append(2);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);
                const callee = fixture.resolved_program.program.statements[1].kind.ExpressionStatement.expression.kind.CallExpression.callee;

                const result = try fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                try expect(result.member_access_by_node_id.get(callee.id).?).toMatch(.{ .ArrayInstanceMethodAccess = .Append });
            }
        };
    };
};
