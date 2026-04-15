const std = @import("std");
const ast = @import("ast");
const helpers = @import("../test_helpers.zig");

const NodeTag = std.meta.Tag(ast.NodeKind);
const TestError = error{UnexpectedNodeKind};

fn expectNodeTag(node: *const ast.Node, expected: NodeTag) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(node.kind));
}

fn expectBinaryExpression(node: *const ast.Node, expected_operator: ast.BinaryOperator) !ast.BinaryExpression {
    const binary_expression = switch (node.kind) {
        .BinaryExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(expected_operator, binary_expression.operator);
    return binary_expression;
}

fn expectUnaryExpression(node: *const ast.Node, expected_operator: ast.UnaryOperator) !ast.UnaryExpression {
    const unary_expression = switch (node.kind) {
        .UnaryExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(expected_operator, unary_expression.operator);
    return unary_expression;
}

test "parser distinguishes statement ifs from expression ifs" {
    const source =
        \\if true { val scoped = 1; }
        \\if true { val left = 1; } else { val right = 2; };
        \\val answer = {
        \\    if true { 1 } else { 2 }
        \\};
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.program.statements.len);
    try expectNodeTag(&parsed.program.statements[0], .IfStatement);

    const expression_statement = switch (parsed.program.statements[1].kind) {
        .ExpressionStatement => |statement| statement,
        else => return TestError.UnexpectedNodeKind,
    };
    try expectNodeTag(expression_statement.expression, .IfExpression);

    const declaration = switch (parsed.program.statements[2].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const block = switch (declaration.value.kind) {
        .Block => |block_value| block_value,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expect(block.result != null);
    try expectNodeTag(block.result.?, .IfExpression);
}

test "parser requires braces for one-branch if bodies" {
    const source =
        \\if true printInt(1);
    ;

    try std.testing.expectError(error.ExpectedLeftBrace, helpers.parseProgram(source));
}

test "parser respects boolean and comparison precedence" {
    const source =
        \\val result = 1 + 2 >= 3 and false or true;
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };

    const or_expression = try expectBinaryExpression(declaration.value, .Or);
    try expectNodeTag(or_expression.right, .BooleanLiteral);

    const and_expression = try expectBinaryExpression(or_expression.left, .And);
    try expectNodeTag(and_expression.right, .BooleanLiteral);

    const comparison_expression = try expectBinaryExpression(and_expression.left, .GreaterThanOrEqual);
    try expectNodeTag(comparison_expression.right, .IntegerLiteral);

    const add_expression = try expectBinaryExpression(comparison_expression.left, .Add);
    try expectNodeTag(add_expression.left, .IntegerLiteral);
    try expectNodeTag(add_expression.right, .IntegerLiteral);
}

test "parser binds unary not tighter than and" {
    const source =
        \\val result = not false and true;
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };

    const and_expression = try expectBinaryExpression(declaration.value, .And);
    _ = try expectUnaryExpression(and_expression.left, .Not);
    try expectNodeTag(and_expression.right, .BooleanLiteral);
}

test "parser allows identifier-led trailing block expressions" {
    const source =
        \\val result = {
        \\    val left = 1;
        \\    val right = 2;
        \\    left + right
        \\};
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const block = switch (declaration.value.kind) {
        .Block => |block_value| block_value,
        else => return TestError.UnexpectedNodeKind,
    };

    try std.testing.expectEqual(@as(usize, 2), block.statements.len);
    try std.testing.expect(block.result != null);
    _ = try expectBinaryExpression(block.result.?, .Add);
}

test "parser keeps block ending with statement if as statement-only block" {
    const source =
        \\{
        \\    if true { val scoped = 1; }
        \\}
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const block = switch (parsed.program.statements[0].kind) {
        .Block => |block_value| block_value,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(@as(usize, 1), block.statements.len);
    try std.testing.expect(block.result == null);
    try expectNodeTag(&block.statements[0], .IfStatement);
}

test "parser parses string literal declarations" {
    const source =
        \\val greeting = "hello world";
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.program.statements.len);
    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    try expectNodeTag(declaration.value, .StringLiteral);
}

test "parser parses string literals as function arguments" {
    const source =
        \\printString("hello");
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.program.statements.len);
    const expression_statement = switch (parsed.program.statements[0].kind) {
        .ExpressionStatement => |statement| statement,
        else => return TestError.UnexpectedNodeKind,
    };
    const call_expression = switch (expression_statement.expression.kind) {
        .CallExpression => |call| call,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(@as(usize, 1), call_expression.arguments.len);
    try expectNodeTag(&call_expression.arguments[0], .StringLiteral);
}

test "parser parses string-typed function definitions" {
    const source =
        \\item echo(x: string): string = x;
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.program.statements.len);
    const function_definition = switch (parsed.program.statements[0].kind) {
        .FunctionDefinition => |definition| definition,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqualStrings("string", function_definition.return_type_annotation.name_token.kind.Identifier);
    try std.testing.expectEqualStrings("string", function_definition.parameters[0].type_annotation.name_token.kind.Identifier);
}

test "parser parses subjectful match expressions" {
    const source =
        \\val message = match true {
        \\    true => "yes",
        \\    false => "no",
        \\};
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const match_expression = switch (declaration.value.kind) {
        .MatchExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };

    try std.testing.expect(match_expression.subject != null);
    try std.testing.expectEqual(@as(usize, 2), match_expression.arms.len);
    try std.testing.expect(match_expression.else_arm == null);
    try expectNodeTag(match_expression.arms[0].pattern_or_condition, .BooleanLiteral);
    try expectNodeTag(match_expression.arms[0].body, .StringLiteral);
}

test "parser parses subjectless match expressions" {
    const source =
        \\val sign = match {
        \\    true => 1,
        \\    else => 0,
        \\};
    ;

    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |value_declaration| value_declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const match_expression = switch (declaration.value.kind) {
        .MatchExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };

    try std.testing.expect(match_expression.subject == null);
    try std.testing.expectEqual(@as(usize, 1), match_expression.arms.len);
    try std.testing.expect(match_expression.else_arm != null);
}
