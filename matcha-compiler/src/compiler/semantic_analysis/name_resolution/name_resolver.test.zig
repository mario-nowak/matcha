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
        .kind = .{ .Union = .{
            .cases = .{
                .{ .name = "PageLoad", .type_reference = .{ .Builtin = .Unit } },
                .{ .name = "PageUnload", .type_reference = .{ .Builtin = .Unit } },
                .{ .name = "KeyPress", .type_reference = .{ .Builtin = .String } },
                .{ .name = "Click", .type_reference = .{ .Builtin = .Integer } },
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
        .kind = .{ .Union = .{
            .cases = .{
                .{ .name = "Status", .type_reference = .{ .Symbol = state_id } },
                .{ .name = "Owner", .type_reference = .{ .Symbol = user_id } },
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
        .kind = .{ .Union = .{
            .cases = .{
                .{ .name = "Leaf", .type_reference = .{ .Builtin = .Integer } },
                .{ .name = "Parent", .type_reference = .{ .Symbol = tree_id } },
                .{ .name = "Children", .type_reference = .{ .Array = .{ .Symbol = tree_id } } },
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
    const function_node = union_node.kind.ItemDefinition.definition.Union.function_definitions[0];
    const body = function_node.kind.ItemDefinition.definition.Function.body_expression;

    const result = try fixture.resolver.resolveProgram(&fixture.program);

    const union_id = result.symbol_id_by_node_id.get(union_node.id).?;
    const function_id = result.symbol_id_by_node_id.get(function_node.id).?;
    const parameter_id = result.symbol_id_by_node_id.get(body.id).?;
    try expect(result.symbol_table.getSymbol(union_id)).toMatch(.{ .kind = .{ .Union = .{ .function_symbol_ids = .{function_id} } } });
    try expect(result.symbol_table.getSymbol(function_id)).toMatch(.{
        .name = "echo",
        .kind = .{ .Function = .{
            .parameter_symbol_ids = .{parameter_id},
            .return_type_reference = .{ .Symbol = union_id },
            .implementation_kind = .UserDefined,
        } },
    });
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "event",
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Symbol = union_id } } },
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
        .kind = .{ .Function = .{ .return_type_reference = .{ .Symbol = union_id } } },
    });
    const parameter_id = function_symbol.kind.Function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "event",
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Symbol = union_id } } },
    });
    try expect(result.symbol_table.getSymbol(binding_id)).toMatch(.{
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Symbol = union_id } } },
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
        .kind = .{ .Structure = .{
            .fields = .{.{ .name = "state", .type_reference = .{ .Symbol = state_id } }},
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
    const member = binding_node.kind.BindingDeclaration.value.kind.MemberExpression;

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
    const call = event_node.kind.BindingDeclaration.value.kind.CallExpression;

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
        .kind = .{ .Structure = .{
            .fields = .{
                .{ .name = "name", .type_reference = .{ .Builtin = .String } },
                .{ .name = "friend", .type_reference = .{ .Symbol = user_id } },
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
        .kind = .{ .Function = .{
            .return_type_reference = .{ .Builtin = .String },
            .implementation_kind = .UserDefined,
        } },
    });
    const parameter_id = greet_symbol.kind.Function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .name = "user",
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Symbol = user_id } } },
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
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Array = .{ .Symbol = user_id } } } },
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
        .kind = .{ .Structure = .{
            .fields = .{
                .{ .name = "friends", .type_reference = .{ .Array = .{ .Symbol = user_id } } },
                .{ .name = "labels", .type_reference = .{ .Array = .{ .Array = .{ .Builtin = .String } } } },
            },
        } },
    });
    const echo_symbol = result.symbol_table.getSymbol(echo_id);
    try expect(echo_symbol).toMatch(.{
        .kind = .{ .Function = .{ .return_type_reference = .{ .Array = .{ .Builtin = .String } } } },
    });
    const parameter_id = echo_symbol.kind.Function.parameter_symbol_ids[0];
    try expect(result.symbol_table.getSymbol(parameter_id)).toMatch(.{
        .kind = .{ .Binding = .{ .declared_type_reference = .{ .Array = .{ .Symbol = user_id } } } },
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
        .kind = .{ .Structure = .{
            .fields = .{
                .{ .name = "organization", .type_reference = .{ .Symbol = organization_id } },
                .{ .name = "name", .type_reference = .{ .Builtin = .String } },
            },
        } },
    });
    try expect(result.symbol_table.getSymbol(organization_id)).toMatch(.{
        .kind = .{ .Structure = .{
            .fields = .{
                .{ .name = "owner", .type_reference = .{ .Symbol = user_id } },
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
    const print_call = for_in_node.kind.ForIn.body_block.kind.Block.statements[0].kind.ExpressionStatement.expression.kind.CallExpression;

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
