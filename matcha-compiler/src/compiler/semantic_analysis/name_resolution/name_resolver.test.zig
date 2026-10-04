const std = @import("std");
const expect = @import("testing").expect;
const setupNameResolverFixture = @import("testing").setupNameResolverFixture;

test "NameResolver > resolveProgram: records union cases with resolved payload types" {
    const source = "item WebEvent = union { PageLoad, PageUnload: unit, KeyPress: string, Click: int, };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);
    const union_node = fixture.program.statements[0];

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const union_symbol_id = result.symbol_id_by_node_id.get(union_node.id).?;
    try expect(result.symbol_table.getSymbol(union_symbol_id)).toMatch(.{
        .name = "WebEvent",
        .kind = .{ .@"union" = .{
            .cases = .{
                .{ .name = "PageLoad", .type_reference = .{ .builtin = .unit } },
                .{ .name = "PageUnload", .type_reference = .{ .builtin = .unit } },
                .{ .name = "KeyPress", .type_reference = .{ .builtin = .string } },
                .{ .name = "Click", .type_reference = .{ .builtin = .integer } },
            },
            .function_symbol_ids = .{},
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves forward union and structure references in payload types" {
    const source =
        \\item Event = union { Status: State, Owner: User, };
        \\item State = union { Ready };
        \\item User = structure { name: string; };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const event_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const state_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[2].id).?;
    try expect(result.symbol_table.getSymbol(event_id)).toMatch(.{
        .kind = .{ .@"union" = .{
            .cases = .{
                .{ .name = "Status", .type_reference = .{ .symbol = state_id } },
                .{ .name = "Owner", .type_reference = .{ .symbol = user_id } },
            },
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves self references and array payload types" {
    const source = "item Tree = union { Leaf: int, Parent: Tree, Children: Tree[], };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const tree_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    try expect(result.symbol_table.getSymbol(tree_id)).toMatch(.{
        .kind = .{ .@"union" = .{
            .cases = .{
                .{ .name = "Leaf", .type_reference = .{ .builtin = .integer } },
                .{ .name = "Parent", .type_reference = .{ .symbol = tree_id } },
                .{ .name = "Children", .type_reference = .{ .array = .{ .symbol = tree_id } } },
            },
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves union function signatures and parameter references" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item echo(event: WebEvent): WebEvent = event;
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);
    const union_node = fixture.program.statements[0];
    const function_node = union_node.kind.item_definition.definition.@"union".function_definitions[0];
    const body = function_node.kind.item_definition.definition.function.body_expression;

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const union_id = result.symbol_id_by_node_id.get(union_node.id).?;
    const function_id = result.symbol_id_by_node_id.get(function_node.id).?;
    const parameter_id = result.symbol_id_by_node_id.get(body.id).?;
    try expect(result.symbol_table.getSymbol(union_id)).toMatch(.{ .kind = .{ .@"union" = .{ .function_symbol_ids = .{function_id} } } });
    try expect(result.symbol_table.getSymbol(function_id)).toMatch(.{
        .name = "echo",
        .kind = .{ .function = .{
            .parameter_symbol_ids = .{parameter_id},
            .return_type_reference = .{ .symbol = union_id },
            .implementation_kind = .user_defined,
        } },
    });
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "event",
        .kind = .{ .binding = .{ .declared_type_reference = .{ .symbol = union_id } } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: accepts unions in function and declaration type annotations" {
    const source =
        \\item echo(event: WebEvent): WebEvent = event;
        \\val event: WebEvent = .PageLoad;
        \\item WebEvent = union { PageLoad };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const function_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const binding_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    const union_id = result.symbol_id_by_node_id.get(fixture.program.statements[2].id).?;
    const function_symbol = result.symbol_table.getSymbol(function_id);
    try expect(function_symbol).toMatch(.{
        .kind = .{ .function = .{ .return_type_reference = .{ .symbol = union_id } } },
    });
    const parameter_id = function_symbol.kind.function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "event",
        .kind = .{ .binding = .{ .declared_type_reference = .{ .symbol = union_id } } },
    });
    try expect(result.symbol_table.getSymbol(binding_id)).toMatch(.{
        .kind = .{ .binding = .{ .declared_type_reference = .{ .symbol = union_id } } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: accepts unions in structure field annotations" {
    const source =
        \\item User = structure { state: State; };
        \\item State = union { Ready };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const state_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    try expect(result.symbol_table.getSymbol(user_id)).toMatch(.{
        .kind = .{ .structure = .{
            .fields = .{.{ .name = "state", .type_reference = .{ .symbol = state_id } }},
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves qualified union bases without binding case members" {
    const source =
        \\item WebEvent = union { PageLoad };
        \\val event = WebEvent.PageLoad;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);
    const union_node = fixture.program.statements[0];
    const binding_node = fixture.program.statements[1];
    const member = binding_node.kind.binding_declaration.value.kind.member_expression;

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const union_id = result.symbol_id_by_node_id.get(union_node.id).?;
    const binding_id = result.symbol_id_by_node_id.get(binding_node.id).?;
    try expect(result.symbol_id_by_node_id).toMatchMap(.{
        .{ .key = union_node.id, .value = union_id },
        .{ .key = member.base.id, .value = union_id },
        .{ .key = binding_node.id, .value = binding_id },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves implicit member call arguments without binding the callee" {
    const source =
        \\item WebEvent = union { KeyPress: string };
        \\val key = "A";
        \\val event: WebEvent = .KeyPress(key);
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);
    const union_node = fixture.program.statements[0];
    const key_node = fixture.program.statements[1];
    const event_node = fixture.program.statements[2];
    const call = event_node.kind.binding_declaration.value.kind.call_expression;

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const union_id = result.symbol_id_by_node_id.get(union_node.id).?;
    const key_id = result.symbol_id_by_node_id.get(key_node.id).?;
    const event_id = result.symbol_id_by_node_id.get(event_node.id).?;
    try expect(result.symbol_id_by_node_id).toMatchMap(.{
        .{ .key = union_node.id, .value = union_id },
        .{ .key = key_node.id, .value = key_id },
        .{ .key = event_node.id, .value = event_id },
        .{ .key = call.arguments[0].id, .value = key_id },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: rejects duplicate union names in module scope" {
    const source = "item Event = union { First }; item Event = union { Second };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "union 'Event' is already defined" },
    });
}

test "NameResolver > resolveProgram: rejects union names that collide with other module items" {
    for ([_][]const u8{
        "item Event = structure { id: int; }; item Event = union { Ready };",
        "item Event(): int = 1; item Event = union { Ready };",
    }) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const fixture = try setupNameResolverFixture(&arena, source);

        const result = fixture.resolver.resolveProgram(&fixture.program);

        try expect(result).toBeError(error.DiagnosticsEmitted);
        try expect(fixture.diagnostic_store.items()).toMatch(.{
            .{ .message = "union 'Event' is already defined" },
        });
    }
}

test "NameResolver > resolveProgram: rejects duplicate union member names" {
    for ([_][]const u8{
        "item Event = union { Ready, Ready };",
        "item Event = union { Ready, item Ready(): int = 1; };",
        "item Event = union { Ready, item value(): int = 1; item value(): int = 2; };",
    }, [_][]const u8{
        "union member 'Ready' is already declared in 'Event'",
        "union member 'Ready' is already declared in 'Event'",
        "union member 'value' is already declared in 'Event'",
    }) |source, message| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const fixture = try setupNameResolverFixture(&arena, source);

        const result = fixture.resolver.resolveProgram(&fixture.program);

        try expect(result).toBeError(error.DiagnosticsEmitted);
        try expect(fixture.diagnostic_store.items()).toMatch(.{
            .{ .message = message },
        });
    }
}

test "NameResolver > resolveProgram: rejects unknown union payload types" {
    const source = "item Event = union { Value: Missing };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "unknown type annotation 'Missing'" },
    });
}

test "NameResolver > resolveProgram: rejects function symbols used as union payload types" {
    const source = "item value(): int = 1; item Event = union { Value: value };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "type annotation 'value' must refer to a structure or union" },
    });
}

test "NameResolver > resolveProgram: keeps union cases out of module scope" {
    const source = "item Event = union { Ready }; val event = Ready;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "undefined identifier 'Ready'" },
    });
}

test "NameResolver > resolveProgram: rejects undefined identifiers inside union functions" {
    const source = "item Event = union { Ready, item value(): int = missing; };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "undefined identifier 'missing'" },
    });
}

test "NameResolver > resolveProgram: rejects reserved names for unions and their members" {
    for ([_][]const u8{
        "item unit = union { Ready };",
        "item Event = union { unit };",
        "item Event = union { Ready, item unit(): int = 1; };",
    }, [_][]const u8{
        "union name 'unit' is reserved",
        "union member name 'unit' is reserved",
        "union member name 'unit' is reserved",
    }) |source, message| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const fixture = try setupNameResolverFixture(&arena, source);

        const result = fixture.resolver.resolveProgram(&fixture.program);

        try expect(result).toBeError(error.DiagnosticsEmitted);
        try expect(fixture.diagnostic_store.items()).toMatch(.{
            .{ .message = message },
        });
    }
}

test "NameResolver > resolveProgram: records structure fields with resolved types" {
    const source = "item User = structure { name: string; friend: User; };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    try expect(result.symbol_table.getSymbol(user_id)).toMatch(.{
        .name = "User",
        .kind = .{ .structure = .{
            .fields = .{
                .{ .name = "name", .type_reference = .{ .builtin = .string } },
                .{ .name = "friend", .type_reference = .{ .symbol = user_id } },
            },
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: records function signatures with typed parameter bindings" {
    const source =
        \\item User = structure { name: string; };
        \\item greet(user: User): string = "hi";
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const greet_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    const greet_symbol = result.symbol_table.getSymbol(greet_id);
    try expect(greet_symbol).toMatch(.{
        .name = "greet",
        .kind = .{ .function = .{
            .return_type_reference = .{ .builtin = .string },
            .implementation_kind = .user_defined,
        } },
    });
    const parameter_id = greet_symbol.kind.function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "user",
        .kind = .{ .binding = .{ .declared_type_reference = .{ .symbol = user_id } } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: records declared type annotations on binding symbols" {
    const source =
        \\item User = structure { name: string; };
        \\val users: User[] = 1;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const declaration_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    try expect(result.symbol_table.getSymbol(declaration_id)).toMatch(.{
        .kind = .{ .binding = .{ .declared_type_reference = .{ .array = .{ .symbol = user_id } } } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves array type expressions recursively" {
    const source =
        \\item User = structure { friends: User[]; labels: string[][]; };
        \\item echo(users: User[]): string[] = "hi";
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const echo_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    try expect(result.symbol_table.getSymbol(user_id)).toMatch(.{
        .kind = .{ .structure = .{
            .fields = .{
                .{ .name = "friends", .type_reference = .{ .array = .{ .symbol = user_id } } },
                .{ .name = "labels", .type_reference = .{ .array = .{ .array = .{ .builtin = .string } } } },
            },
        } },
    });
    const echo_symbol = result.symbol_table.getSymbol(echo_id);
    try expect(echo_symbol).toMatch(.{
        .kind = .{ .function = .{ .return_type_reference = .{ .array = .{ .builtin = .string } } } },
    });
    const parameter_id = echo_symbol.kind.function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .kind = .{ .binding = .{ .declared_type_reference = .{ .array = .{ .symbol = user_id } } } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves forward structure references in field type annotations" {
    const source =
        \\item User = structure { organization: Organization; name: string; };
        \\item Organization = structure { owner: User; };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const user_id = result.symbol_id_by_node_id.get(fixture.program.statements[0].id).?;
    const organization_id = result.symbol_id_by_node_id.get(fixture.program.statements[1].id).?;
    try expect(result.symbol_table.getSymbol(user_id)).toMatch(.{
        .kind = .{ .structure = .{
            .fields = .{
                .{ .name = "organization", .type_reference = .{ .symbol = organization_id } },
                .{ .name = "name", .type_reference = .{ .builtin = .string } },
            },
        } },
    });
    try expect(result.symbol_table.getSymbol(organization_id)).toMatch(.{
        .kind = .{ .structure = .{
            .fields = .{
                .{ .name = "owner", .type_reference = .{ .symbol = user_id } },
            },
        } },
    });
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: resolves for-in item bindings inside loop bodies" {
    const source =
        \\val numbers = [1, 2, 3];
        \\for number in numbers {
        \\    printInt(number);
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);
    const for_in_node = fixture.program.statements[1];
    const print_call = for_in_node.kind.for_in.body_block.kind.block.statements[0].kind.expression_statement.expression.kind.call_expression;

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const item_id = result.symbol_id_by_node_id.get(for_in_node.id).?;
    const body_identifier_id = result.symbol_id_by_node_id.get(print_call.arguments[0].id).?;
    try std.testing.expectEqual(item_id, body_identifier_id);
    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "NameResolver > resolveProgram: rejects declarations that use reserved builtin type names" {
    const source = "val unit = 1;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupNameResolverFixture(&arena, source);

    const result = fixture.resolver.resolveProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "value name 'unit' is reserved" },
    });
}

pub const NameResolver = struct {
    pub const resolveProgram = struct {
        pub const match_expression = struct {
            test "resolves a payload binding in its arm body" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .None => printString("None"),
                    \\    .Some(value) => printInt(value),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);
                const match_node = fixture.program.statements[2].kind.expression_statement.expression;
                const second_match_arm = match_node.kind.match_expression.arms[1];
                const print_call_argument = second_match_arm.body_expression.kind.call_expression.arguments[0];

                const result = try fixture.resolver.resolveProgram(&fixture.program);

                const value_pattern_symbol_id = result.symbol_id_by_node_id.get(second_match_arm.pattern.kind.case.binding.?.id).?;
                const value_body_symbol_id = result.symbol_id_by_node_id.get(print_call_argument.id).?;
                try expect(value_body_symbol_id).toMatch(value_pattern_symbol_id);
                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }

            test "keeps a payload binding out of the other arms" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(value) => printInt(value),
                    \\    .None => printInt(value),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "undefined identifier 'value'" },
                });
            }

            test "keeps a payload binding out of the else arm" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(value) => printInt(value),
                    \\    else => printInt(value),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "undefined identifier 'value'" },
                });
            }

            test "keeps a payload binding out of statements after the match" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(value) => printInt(value),
                    \\    else => printInt(0),
                    \\};
                    \\printInt(value);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "undefined identifier 'value'" },
                });
            }

            test "gives payload bindings with the same name in two arms separate symbols" {
                const source =
                    \\item Pair = union { First: int, Second: int };
                    \\val pair = .First(1);
                    \\match pair {
                    \\    .First(value) => printInt(value),
                    \\    .Second(value) => printInt(value),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);
                const match_node = fixture.program.statements[2].kind.expression_statement.expression;
                const first_match_arm = match_node.kind.match_expression.arms[0];
                const second_match_arm = match_node.kind.match_expression.arms[1];

                const result = try fixture.resolver.resolveProgram(&fixture.program);

                const first_value_symbol_id = result.symbol_id_by_node_id.get(first_match_arm.pattern.kind.case.binding.?.id).?;
                const second_value_symbol_id = result.symbol_id_by_node_id.get(second_match_arm.pattern.kind.case.binding.?.id).?;
                try std.testing.expect(first_value_symbol_id != second_value_symbol_id);
            }

            test "records a payload binding as an immutable binding symbol" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(value) => printInt(value),
                    \\    else => printInt(0),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);
                const match_node = fixture.program.statements[2].kind.expression_statement.expression;
                const some_match_arm = match_node.kind.match_expression.arms[0];

                const result = try fixture.resolver.resolveProgram(&fixture.program);

                const value_symbol_id = result.symbol_id_by_node_id.get(some_match_arm.pattern.kind.case.binding.?.id).?;
                try expect(result.symbol_table.getSymbol(value_symbol_id)).toMatch(.{
                    .name = "value",
                    .kind = .{ .binding = .{ .binding_mutability = .immutable } },
                });
            }

            test "records no symbol for a case pattern without a qualifier" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .None => printInt(0),
                    \\    else => printInt(1),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);
                const match_node = fixture.program.statements[2].kind.expression_statement.expression;
                const none_match_arm = match_node.kind.match_expression.arms[0];

                const result = try fixture.resolver.resolveProgram(&fixture.program);

                try expect(result.symbol_id_by_node_id.get(none_match_arm.pattern.id)).toMatch(null);
            }

            test "rejects unit as a payload binding name" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(unit) => printInt(0),
                    \\    else => printInt(1),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "payload binding name 'unit' is reserved" },
                });
            }

            test "rejects a payload binding with the name of a parameter" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\item describe(result: Result, value: int): int = match result {
                    \\    .Some(value) => value,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "payload binding 'value' is already declared in this scope" },
                });
            }

            test "rejects a payload binding with the name of a binding in an enclosing block" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\item describe(result: Result): int = {
                    \\    val value = 1;
                    \\    match result {
                    \\        .Some(value) => value,
                    \\        else => 0,
                    \\    }
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "payload binding 'value' is already declared in this scope" },
                });
            }

            test "rejects a payload binding with the name of a payload binding in an enclosing arm" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\item describe(outer: Result, inner: Result): int = match outer {
                    \\    .Some(value) => match inner {
                    \\        .Some(value) => value,
                    \\        else => 0,
                    \\    },
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "payload binding 'value' is already declared in this scope" },
                });
            }

            test "rejects a payload binding with the name of a module item outside functions" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    .Some(printString) => printInt(0),
                    \\    else => printInt(1),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "payload binding 'printString' is already declared in module scope" },
                });
            }

            test "lets a payload binding shadow a module item inside a function" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\item value(): int = 1;
                    \\item describe(result: Result): int = match result {
                    \\    .Some(value) => value,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                _ = try fixture.resolver.resolveProgram(&fixture.program);

                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }

            test "resolves the qualifier of a case pattern to the union" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    Result.None => printInt(0),
                    \\    else => printInt(1),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);
                const union_node = fixture.program.statements[0];
                const match_node = fixture.program.statements[2].kind.expression_statement.expression;
                const none_match_arm = match_node.kind.match_expression.arms[0];

                const result = try fixture.resolver.resolveProgram(&fixture.program);

                const union_symbol_id = result.symbol_id_by_node_id.get(union_node.id).?;
                try expect(result.symbol_id_by_node_id.get(none_match_arm.pattern.id).?).toMatch(union_symbol_id);
            }

            test "rejects an undefined qualifier in a case pattern" {
                const source =
                    \\item Result = union { None, Some: int };
                    \\val result = .Some(1);
                    \\match result {
                    \\    Missing.None => printInt(0),
                    \\    else => printInt(1),
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "undefined identifier 'Missing'" },
                });
            }
        };

        pub const for_in = struct {
            test "rejects a for-in binding with the name of a parameter" {
                const source =
                    \\item sum(numbers: int[], number: int): int = {
                    \\    for number in numbers {
                    \\        printInt(number);
                    \\    }
                    \\    return 0;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "for-in binding 'number' is already declared in this scope" },
                });
            }

            test "rejects a for-in binding with the name of a binding in an enclosing block" {
                const source =
                    \\item sum(numbers: int[]): int = {
                    \\    val number = 1;
                    \\    for number in numbers {
                    \\        printInt(number);
                    \\    }
                    \\    return 0;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "for-in binding 'number' is already declared in this scope" },
                });
            }

            test "rejects a for-in binding with the name of a for-in binding in an enclosing loop" {
                const source =
                    \\item sum(numbers: int[]): int = {
                    \\    for number in numbers {
                    \\        for number in numbers {
                    \\            printInt(number);
                    \\        }
                    \\    }
                    \\    return 0;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "for-in binding 'number' is already declared in this scope" },
                });
            }

            test "rejects a for-in binding with the name of a module item outside functions" {
                const source =
                    \\val numbers = [1, 2, 3];
                    \\for printString in numbers {
                    \\    printInt(printString);
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "for-in binding 'printString' is already declared in module scope" },
                });
            }

            test "lets a for-in binding shadow a module item inside a function" {
                const source =
                    \\item number(): int = 1;
                    \\item sum(numbers: int[]): int = {
                    \\    for number in numbers {
                    \\        printInt(number);
                    \\    }
                    \\    return 0;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                _ = try fixture.resolver.resolveProgram(&fixture.program);

                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }
        };

        pub const builtin_functions = struct {
            test "rejects a function with the name of a builtin function" {
                const source =
                    \\item printInt(value: int): unit = unit;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "function 'printInt' is already defined" },
                });
            }

            test "rejects a structure with the name of a builtin function" {
                const source =
                    \\item printInt = structure { value: int; };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "structure 'printInt' is already defined" },
                });
            }

            test "rejects a union with the name of a builtin function" {
                const source =
                    \\item printInt = union { None, Some: int };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "union 'printInt' is already defined" },
                });
            }

            test "rejects a module-level binding with the name of a builtin function" {
                const source =
                    \\val printInt = 1;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupNameResolverFixture(&arena, source);

                const result = fixture.resolver.resolveProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "value 'printInt' is already declared in module scope" },
                });
            }
        };
    };
};
