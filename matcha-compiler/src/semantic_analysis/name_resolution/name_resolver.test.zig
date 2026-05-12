const std = @import("std");
const lexing = @import("lexing");
const parsing = @import("parsing");
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

fn parseProgram(source: []const u8) !ParsedProgram {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();

    const allocator = arena.allocator();
    const owned_source = try allocator.dupe(u8, source);

    var lexer = lexing.Lexer.init(owned_source, allocator);
    defer lexer.deinit();

    var parser = parsing.Parser.init(lexer, allocator);
    const program = try parser.parse();

    return .{
        .arena = arena,
        .program = program,
    };
}

test "name resolution emits resolved structures and functions" {
    var parsed = try parseProgram(
        \\item User = structure { name: string; friend: User; };
        \\item greet(user: User): string = "hi";
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    const resolved_program = try name_resolver.resolveProgram(&parsed.program);

    const user_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[0].id).?;
    const greet_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[1].id).?;

    const user_structure = resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
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

    const greet_function = resolved_program.resolved_function_by_symbol_id.get(greet_symbol_id).?;
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
    try std.testing.expectEqualStrings("user", greet_function.parameters[0].name);
}

test "name resolution resolves declaration type annotations into side table" {
    var parsed = try parseProgram(
        \\item User = structure { name: string; };
        \\val users: User[] = 1;
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    const resolved_program = try name_resolver.resolveProgram(&parsed.program);

    const declaration = switch (parsed.program.statements[1].kind) {
        .Declaration => |declaration| declaration,
        else => return error.UnexpectedNodeKind,
    };
    const user_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[0].id).?;
    const declaration_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[1].id).?;

    _ = declaration;

    switch (resolved_program.annotated_type_reference_by_symbol_id.get(declaration_symbol_id).?) {
        .Array => |element_type_reference| switch (element_type_reference.*) {
            .Symbol => |symbol_id| try std.testing.expectEqual(user_symbol_id, symbol_id),
            else => return error.UnexpectedTypeReferenceKind,
        },
        else => return error.UnexpectedTypeReferenceKind,
    }
}

test "name resolution resolves array type expressions recursively" {
    var parsed = try parseProgram(
        \\item User = structure { friends: User[]; labels: string[][]; };
        \\item echo(users: User[]): string[] = "hi";
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    const resolved_program = try name_resolver.resolveProgram(&parsed.program);

    const user_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[0].id).?;
    const echo_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[1].id).?;

    const user_structure = resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
    const echo_function = resolved_program.resolved_function_by_symbol_id.get(echo_symbol_id).?;

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
    var parsed = try parseProgram(
        \\item User = structure { organization: Organization; name: string; };
        \\item Organization = structure { owner: User; };
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    const resolved_program = try name_resolver.resolveProgram(&parsed.program);

    const user_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[0].id).?;
    const organization_symbol_id = resolved_program.symbol_id_by_node_id.get(parsed.program.statements[1].id).?;

    const user_structure = resolved_program.resolved_structure_by_symbol_id.get(user_symbol_id).?;
    const organization_structure = resolved_program.resolved_structure_by_symbol_id.get(organization_symbol_id).?;

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

test "name resolution rejects function symbols in type annotations" {
    var parsed = try parseProgram(
        \\item helper(): int = 1;
        \\item User = structure { bad: helper; };
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    try std.testing.expectError(error.InvalidTypeAnnotation, name_resolver.resolveProgram(&parsed.program));
}

test "name resolution rejects structure field and type function name collisions" {
    var parsed = try parseProgram(
        \\item User = structure {
        \\    name: string;
        \\    item name(): string = "duplicate";
        \\};
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    try std.testing.expectError(error.StructureMemberNameCollision, name_resolver.resolveProgram(&parsed.program));
}

test "name resolution rejects duplicate structure type function names" {
    var parsed = try parseProgram(
        \\item User = structure {
        \\    id: int;
        \\    item format(): string = "a";
        \\    item format(): string = "b";
        \\};
    );
    defer parsed.deinit();

    var name_resolver = semantic_analysis.name_resolution.NameResolver.init(parsed.allocator());
    try std.testing.expectError(error.StructureMemberNameCollision, name_resolver.resolveProgram(&parsed.program));
}
