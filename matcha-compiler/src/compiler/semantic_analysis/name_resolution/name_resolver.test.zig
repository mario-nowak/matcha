const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
const diagnostics = @import("diagnostics");
const semantic_analysis = @import("semantic_analysis");

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
    resolved_program: semantic_analysis.name_resolution.ResolvedProgram,

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
    const user_structure = resolved.resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
    try std.testing.expectEqual(user_symbol_id, user_structure.symbol_id);
    try std.testing.expectEqualStrings("User", user_structure.name);
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
    const greet_function = resolved.resolved_program.resolved_function_by_symbol_id.get(greet_symbol_id).?;
    try std.testing.expectEqual(greet_symbol_id, greet_function.symbol_id);
    try std.testing.expectEqualStrings("greet", greet_function.name);
    try std.testing.expectEqual(@as(usize, 1), greet_function.parameters.len);
    try std.testing.expectEqualStrings("user", greet_function.parameters[0].name);
    switch (greet_function.parameters[0].type_reference) {
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
    switch (resolved.resolved_program.annotated_type_reference_by_symbol_id.get(declaration_symbol_id).?) {
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
    const user_structure = resolved.resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
    const echo_function = resolved.resolved_program.resolved_function_by_symbol_id.get(echo_symbol_id).?;
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
    switch (echo_function.parameters[0].type_reference) {
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
    const user_structure = resolved.resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
    const organization_structure = resolved.resolved_program.resolved_structure_by_symbol_id.get(organization_symbol_id).?;
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
