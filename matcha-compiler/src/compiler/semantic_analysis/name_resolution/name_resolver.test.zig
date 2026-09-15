const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
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

const ParsedProgram = struct {
    arena: std.heap.ArenaAllocator,
    program: @import("ast").Program,

    fn allocator(self: *ParsedProgram) std.mem.Allocator {
        return self.arena.allocator();
    }

    fn deinit(self: *ParsedProgram) void {
        self.arena.deinit();
    }
};

const ResolvedTestProgram = struct {
    parsed: ParsedProgram,
    resolved_program: symbols.ResolvedProgram,

    fn deinit(self: *ResolvedTestProgram) void {
        self.parsed.deinit();
    }
};

fn parse(source: []const u8) !ParsedProgram {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, source);

    var diagnostic_store = diagnostics.DiagnosticStore.init(allocator);
    defer diagnostic_store.deinit();

    var lexer = lexing.Lexer.init(owned_source, allocator, &diagnostic_store);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator, &diagnostic_store);
    const program = try parser.parse();

    return .{
        .arena = arena,
        .program = program,
    };
}

fn resolve(source: []const u8) !ResolvedTestProgram {
    var parsed = try parse(source);
    errdefer parsed.deinit();

    var diagnostic_store = diagnostics.DiagnosticStore.init(parsed.allocator());
    defer diagnostic_store.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator(), &diagnostic_store);
    const resolved_program = try name_resolver.resolveProgram(&parsed.program);

    return .{
        .parsed = parsed,
        .resolved_program = resolved_program,
    };
}

test "name resolution emits resolved structures and functions" {
    const source =
        \\item User = structure { name: string; friend: User; };
        \\item greet(user: User): string = "hi";
    ;

    var resolved = try resolve(source);
    defer resolved.deinit();

    const user_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[0].id).?;
    const greet_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[1].id).?;
    const user_symbol = resolved.resolved_program.symbol_table.getSymbol(user_symbol_id);
    try std.testing.expectEqualStrings("User", user_symbol.name);
    const user_structure = switch (user_symbol.kind) {
        .Structure => |structure_information| structure_information,
        else => return error.UnexpectedSymbolKind,
    };
    try std.testing.expectEqual(@as(usize, 2), user_structure.fields.len);
    try std.testing.expectEqualStrings("name", user_structure.fields[0].name);
    switch (user_structure.fields[0].type_reference) {
        .Builtin => |builtin| try std.testing.expectEqual(.String, builtin),
        else => return error.UnexpectedTypeReferenceKind,
    }
    try std.testing.expectEqualStrings("friend", user_structure.fields[1].name);
    switch (user_structure.fields[1].type_reference) {
        .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
        else => return error.UnexpectedTypeReferenceKind,
    }
    const greet_symbol = resolved.resolved_program.symbol_table.getSymbol(greet_symbol_id);
    try std.testing.expectEqualStrings("greet", greet_symbol.name);
    const greet_function = switch (greet_symbol.kind) {
        .Function => |function_information| function_information,
        else => return error.UnexpectedSymbolKind,
    };
    try std.testing.expectEqual(@as(usize, 1), greet_function.parameter_symbol_ids.len);
    const greet_parameter_symbol = resolved.resolved_program.symbol_table.getSymbol(greet_function.parameter_symbol_ids[0]);
    try std.testing.expectEqualStrings("user", greet_parameter_symbol.name);
    const greet_parameter_type_reference = switch (greet_parameter_symbol.kind) {
        .Binding => |binding_information| binding_information.declared_type_reference.?,
        else => return error.UnexpectedSymbolKind,
    };
    switch (greet_parameter_type_reference) {
        .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
        else => return error.UnexpectedTypeReferenceKind,
    }
    switch (greet_function.return_type_reference) {
        .Builtin => |builtin| try std.testing.expectEqual(.String, builtin),
        else => return error.UnexpectedTypeReferenceKind,
    }
}

test "name resolution resolves declaration type annotations into side table" {
    const source =
        \\item User = structure { name: string; };
        \\val users: User[] = 1;
    ;

    var resolved = try resolve(source);
    defer resolved.deinit();

    const user_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[0].id).?;
    const declaration_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[1].id).?;
    const declaration_type_reference = switch (resolved.resolved_program.symbol_table.getSymbol(declaration_symbol_id).kind) {
        .Binding => |binding_information| binding_information.declared_type_reference.?,
        else => return error.UnexpectedSymbolKind,
    };
    switch (declaration_type_reference) {
        .Array => |element_type_reference| switch (element_type_reference.*) {
            .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
}

test "name resolution resolves array type expressions recursively" {
    const source =
        \\item User = structure { friends: User[]; labels: string[][]; };
        \\item echo(users: User[]): string[] = "hi";
    ;

    var resolved = try resolve(source);
    defer resolved.deinit();

    const user_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[0].id).?;
    const echo_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[1].id).?;
    const user_structure = switch (resolved.resolved_program.symbol_table.getSymbol(user_symbol_id).kind) {
        .Structure => |structure_information| structure_information,
        else => return error.UnexpectedSymbolKind,
    };
    const echo_function = switch (resolved.resolved_program.symbol_table.getSymbol(echo_symbol_id).kind) {
        .Function => |function_information| function_information,
        else => return error.UnexpectedSymbolKind,
    };
    switch (user_structure.fields[0].type_reference) {
        .Array => |element_type_reference| switch (element_type_reference.*) {
            .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
    switch (user_structure.fields[1].type_reference) {
        .Array => |outer_element_type_reference| switch (outer_element_type_reference.*) {
            .Array => |inner_element_type_reference| switch (inner_element_type_reference.*) {
                .Builtin => |builtin| try std.testing.expectEqual(.String, builtin),
                else => return error.UnexpectedTypeReferenceKind,
            },
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
    const echo_parameter_type_reference = switch (resolved.resolved_program.symbol_table.getSymbol(echo_function.parameter_symbol_ids[0]).kind) {
        .Binding => |binding_information| binding_information.declared_type_reference.?,
        else => return error.UnexpectedSymbolKind,
    };
    switch (echo_parameter_type_reference) {
        .Array => |element_type_reference| switch (element_type_reference.*) {
            .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
    switch (echo_function.return_type_reference) {
        .Array => |element_type_reference| switch (element_type_reference.*) {
            .Builtin => |builtin| try std.testing.expectEqual(.String, builtin),
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
}

test "name resolution resolves forward structure references in field type annotations" {
    const source =
        \\item User = structure { organization: Organization; name: string; };
        \\item Organization = structure { owner: User; };
    ;

    var resolved = try resolve(source);
    defer resolved.deinit();

    const user_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[0].id).?;
    const organization_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[1].id).?;
    const user_structure = switch (resolved.resolved_program.symbol_table.getSymbol(user_symbol_id).kind) {
        .Structure => |structure_information| structure_information,
        else => return error.UnexpectedSymbolKind,
    };
    const organization_structure = switch (resolved.resolved_program.symbol_table.getSymbol(organization_symbol_id).kind) {
        .Structure => |structure_information| structure_information,
        else => return error.UnexpectedSymbolKind,
    };
    switch (user_structure.fields[0].type_reference) {
        .Symbol => |symbol_id| try std.testing.expectEqual(organization_symbol_id, symbol_id),
        else => return error.UnexpectedTypeReferenceKind,
    }
    switch (user_structure.fields[1].type_reference) {
        .Builtin => |builtin| try std.testing.expectEqual(.String, builtin),
        else => return error.UnexpectedTypeReferenceKind,
    }
    switch (organization_structure.fields[0].type_reference) {
        .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
        else => return error.UnexpectedTypeReferenceKind,
    }
}

test "name resolution resolves for-in item bindings inside loop bodies" {
    const source =
        \\val numbers = [1, 2, 3];
        \\for number in numbers {
        \\    printInt(number);
        \\}
    ;

    var resolved = try resolve(source);
    defer resolved.deinit();

    const for_in = switch (resolved.parsed.program.statements[1].kind) {
        .ForIn => |for_in_statement| for_in_statement,
        else => return error.UnexpectedNodeKind,
    };
    const body_block = switch (for_in.body_block.kind) {
        .Block => |block| block,
        else => return error.UnexpectedNodeKind,
    };
    const print_statement = switch (body_block.statements[0].kind) {
        .ExpressionStatement => |statement| statement,
        else => return error.UnexpectedNodeKind,
    };
    const print_call = switch (print_statement.expression.kind) {
        .CallExpression => |call| call,
        else => return error.UnexpectedNodeKind,
    };
    const for_item_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(resolved.parsed.program.statements[1].id).?;
    const body_identifier_symbol_id = resolved.resolved_program.symbol_id_by_node_id.get(print_call.arguments[0].id).?;
    try std.testing.expectEqual(for_item_symbol_id, body_identifier_symbol_id);
}

test "name resolution reserves builtin type names for declarations" {
    const source =
        \\val unit = 1;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    var diagnostic_store = diagnostics.DiagnosticStore.init(parsed.allocator());
    defer diagnostic_store.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator(), &diagnostic_store);
    try std.testing.expectError(error.DiagnosticsEmitted, name_resolver.resolveProgram(&parsed.program));

    const diagnostic_items = diagnostic_store.items();
    try std.testing.expectEqual(@as(usize, 1), diagnostic_items.len);
    try std.testing.expectEqualStrings("value name 'unit' is reserved", diagnostic_items[0].message);
}
