const std = @import("std");
const ast = @import("ast");
const helpers = @import("../test_helpers.zig");
const emission = @import("emission");
const CallLowerer = emission.lowering.CallLowerer;

const TestError = helpers.TestError;
const expectDeclarationNode = helpers.expectDeclarationNode;
const expectCallExpressionNode = helpers.expectCallExpressionNode;

fn expectExpressionStatement(node: *const ast.Node) TestError!ast.ExpressionStatement {
    return switch (node.kind) {
        .ExpressionStatement => |expression_statement| expression_statement,
        else => return TestError.UnexpectedNodeKind,
    };
}

test "call lowering records direct builtin and structure call strategies" {
    const source =
        \\item identity(value: int): int = value;
        \\item Point = structure {
        \\    x: int;
        \\
        \\    item origin(): Point = Point { x = 0 };
        \\    item moved(self: Point): Point = self;
        \\};
        \\val point = Point.origin();
        \\val copied = identity(1);
        \\val moved = point.moved();
        \\printString("hello");
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    var lowerer = CallLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const decisions = lowerer.lower(&analyzed.typed_program);
    const point_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[1].id).?;

    const point_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    _ = try expectCallExpressionNode(point_declaration.value);
    switch (decisions.get(point_declaration.value.id).?) {
        .UserFunction => |user_function| {
            try std.testing.expectEqual(point_symbol_id, user_function.owning_structure_symbol_id.?);
            try std.testing.expect(user_function.receiver_node_id == null);
        },
        else => return TestError.UnexpectedNodeKind,
    }

    const copied_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);
    _ = try expectCallExpressionNode(copied_declaration.value);
    switch (decisions.get(copied_declaration.value.id).?) {
        .UserFunction => |user_function| {
            try std.testing.expect(user_function.owning_structure_symbol_id == null);
            try std.testing.expect(user_function.receiver_node_id == null);
            const function_symbol = analyzed.typed_program.resolved_program.symbol_table.getSymbol(user_function.function_symbol_id);
            try std.testing.expectEqualStrings("identity", function_symbol.name);
        },
        else => return TestError.UnexpectedNodeKind,
    }

    const moved_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[4]);
    const moved_call = try expectCallExpressionNode(moved_declaration.value);
    const moved_callee = switch (moved_call.callee.kind) {
        .MemberAccess => |member_access| member_access,
        else => return TestError.UnexpectedNodeKind,
    };
    switch (decisions.get(moved_declaration.value.id).?) {
        .UserFunction => |user_function| {
            try std.testing.expectEqual(point_symbol_id, user_function.owning_structure_symbol_id.?);
            try std.testing.expectEqual(moved_callee.base.id, user_function.receiver_node_id.?);
            const function_symbol = analyzed.typed_program.resolved_program.symbol_table.getSymbol(user_function.function_symbol_id);
            try std.testing.expectEqualStrings("moved", function_symbol.name);
        },
        else => return TestError.UnexpectedNodeKind,
    }

    const print_statement = try expectExpressionStatement(&analyzed.parsed.program.statements[5]);
    _ = try expectCallExpressionNode(print_statement.expression);
    switch (decisions.get(print_statement.expression.id).?) {
        .Builtin => |builtin| try std.testing.expectEqual(.PrintString, builtin),
        else => return TestError.UnexpectedNodeKind,
    }
}

test "call lowering records array string integer and io helper strategies" {
    const source =
        \\val input = readFile("input.txt");
        \\val trimmed = input.trim();
        \\val parts = trimmed.split(",");
        \\val first = parts[0].toInt();
        \\val text = first.toString();
        \\val line = readLine();
        \\val args = getArguments();
        \\val numbers = [1, 2, 3];
        \\numbers.append(4);
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    var lowerer = CallLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const decisions = lowerer.lower(&analyzed.typed_program);

    const input_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[0]);
    switch (decisions.get(input_declaration.value.id).?) {
        .Builtin => |builtin| try std.testing.expectEqual(.ReadFile, builtin),
        else => return TestError.UnexpectedNodeKind,
    }

    const trimmed_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    switch (decisions.get(trimmed_declaration.value.id).?) {
        .StringMethod => |string_method| try std.testing.expectEqual(.Trim, string_method),
        else => return TestError.UnexpectedNodeKind,
    }

    const parts_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    switch (decisions.get(parts_declaration.value.id).?) {
        .StringMethod => |string_method| try std.testing.expectEqual(.Split, string_method),
        else => return TestError.UnexpectedNodeKind,
    }

    const first_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);
    switch (decisions.get(first_declaration.value.id).?) {
        .StringMethod => |string_method| try std.testing.expectEqual(.ToInt, string_method),
        else => return TestError.UnexpectedNodeKind,
    }

    const text_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[4]);
    switch (decisions.get(text_declaration.value.id).?) {
        .IntegerMethod => |integer_method| try std.testing.expectEqual(.ToString, integer_method),
        else => return TestError.UnexpectedNodeKind,
    }

    const line_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[5]);
    switch (decisions.get(line_declaration.value.id).?) {
        .Builtin => |builtin| try std.testing.expectEqual(.ReadLine, builtin),
        else => return TestError.UnexpectedNodeKind,
    }

    const args_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[6]);
    switch (decisions.get(args_declaration.value.id).?) {
        .Builtin => |builtin| try std.testing.expectEqual(.GetArguments, builtin),
        else => return TestError.UnexpectedNodeKind,
    }

    const append_statement = try expectExpressionStatement(&analyzed.parsed.program.statements[8]);
    switch (decisions.get(append_statement.expression.id).?) {
        .ArrayMethod => |array_method| try std.testing.expectEqual(.Append, array_method),
        else => return TestError.UnexpectedNodeKind,
    }
}
