const std = @import("std");
const ast = @import("ast");
const helpers = @import("../test_helpers.zig");

const NodeTag = std.meta.Tag(ast.NodeKind);
const TestError = helpers.TestError;

const expectDeclarationNode = helpers.expectDeclarationNode;
const expectBlockNode = helpers.expectBlockNode;
const expectWhileNode = helpers.expectWhileNode;
const expectForInNode = helpers.expectForInNode;
const expectItemDefinitionNode = helpers.expectItemDefinitionNode;
const expectMatchExpressionNode = helpers.expectMatchExpressionNode;
const expectIndexAccessNode = helpers.expectIndexAccessNode;

fn parse(source: []const u8) !helpers.ParsedProgram {
    return helpers.parseProgram(source);
}

fn expectNodeTag(node: *const ast.Node, expected: NodeTag) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(node.kind));
}

fn expectStructureDefinition(item_definition: ast.ItemDefinition) !ast.Structure {
    return switch (item_definition.item) {
        .Structure => |structure| structure,
        else => return TestError.UnexpectedNodeKind,
    };
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

fn expectMemberAccess(node: *const ast.Node, expected_member_name: []const u8) !ast.MemberAccess {
    const member_access = switch (node.kind) {
        .MemberAccess => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqualStrings(expected_member_name, member_access.member_name_token.kind.Identifier);
    return member_access;
}

fn expectAssignment(node: *const ast.Node) !ast.Assignment {
    return switch (node.kind) {
        .Assignment => |assignment| assignment,
        else => return TestError.UnexpectedNodeKind,
    };
}

test "parser respects boolean and comparison precedence" {
    const source =
        \\val result = 1 + 2 >= 3 and false or true;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
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

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
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

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const block = try expectBlockNode(declaration.value);
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

    var parsed = try parse(source);
    defer parsed.deinit();

    const block = try expectBlockNode(&parsed.program.statements[0]);
    try std.testing.expectEqual(@as(usize, 1), block.statements.len);
    try std.testing.expect(block.result == null);
    try expectNodeTag(&block.statements[0], .IfStatement);
}

test "parser treats bare identifier while conditions as conditions, not structure construction" {
    const source =
        \\while is_ready {
        \\    continue;
        \\}
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const while_statement = try expectWhileNode(&parsed.program.statements[0]);
    try expectNodeTag(while_statement.condition, .Identifier);
}

test "parser treats unit as a literal in expression context" {
    const source =
        \\val value = unit;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    try expectNodeTag(declaration.value, .UnitLiteral);
}

test "parser treats item as a contextual definition keyword" {
    const source =
        \\val item = 1;
        \\for item in items {
        \\    printInt(item);
        \\}
        \\item Point = structure {
        \\    item: int;
        \\    item get(self: Point): int = self.item;
        \\};
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const for_in = try expectForInNode(&parsed.program.statements[1]);
    const structure_definition = try expectStructureDefinition(try expectItemDefinitionNode(&parsed.program.statements[2]));
    try std.testing.expectEqualStrings("item", declaration.name.kind.Identifier);
    try std.testing.expectEqualStrings("item", for_in.item_name.kind.Identifier);
    try std.testing.expectEqualStrings("item", structure_definition.fields[0].name.kind.Identifier);
    try std.testing.expectEqual(@as(usize, 1), structure_definition.function_definitions.len);
}

test "parser parses structure member access expressions" {
    const source =
        \\val x = point.x;
        \\val y = user.location.x;
        \\val z = (Point { x = 1, y = 2 }).x;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const x_declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const y_declaration = try expectDeclarationNode(&parsed.program.statements[1]);
    const z_declaration = try expectDeclarationNode(&parsed.program.statements[2]);
    const point_x = try expectMemberAccess(x_declaration.value, "x");
    try expectNodeTag(point_x.base, .Identifier);
    const user_location_x = try expectMemberAccess(y_declaration.value, "x");
    const user_location = try expectMemberAccess(user_location_x.base, "location");
    try expectNodeTag(user_location.base, .Identifier);
    const constructed_point_x = try expectMemberAccess(z_declaration.value, "x");
    try expectNodeTag(constructed_point_x.base, .StructureConstruction);
}

test "parser parses anonymous structure literal expressions" {
    const source =
        \\val point = .{ x = 1, y = 2 };
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const anonymous_literal = switch (declaration.value.kind) {
        .AnonymousStructureLiteral => |literal| literal,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(@as(usize, 2), anonymous_literal.fields.len);
}

test "parser parses structure member assignment statements" {
    const source =
        \\point.x = 3;
        \\user.location.x = 4;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const first_assignment = try expectAssignment(&parsed.program.statements[0]);
    const second_assignment = try expectAssignment(&parsed.program.statements[1]);
    const point_x = try expectMemberAccess(first_assignment.target, "x");
    try expectNodeTag(point_x.base, .Identifier);
    try expectNodeTag(first_assignment.value, .IntegerLiteral);
    const user_location_x = try expectMemberAccess(second_assignment.target, "x");
    const user_location = try expectMemberAccess(user_location_x.base, "location");
    try expectNodeTag(user_location.base, .Identifier);
    try expectNodeTag(second_assignment.value, .IntegerLiteral);
}

test "parser parses indexed and mixed place assignment statements" {
    const source =
        \\numbers[0] = 4;
        \\user.points[i].x = 1;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const indexed_assignment = try expectAssignment(&parsed.program.statements[0]);
    const mixed_assignment = try expectAssignment(&parsed.program.statements[1]);
    const indexed_target = try expectIndexAccessNode(indexed_assignment.target);
    try expectNodeTag(indexed_target.base, .Identifier);
    try expectNodeTag(indexed_target.index, .IntegerLiteral);
    try expectNodeTag(indexed_assignment.value, .IntegerLiteral);
    const points_i_x = try expectMemberAccess(mixed_assignment.target, "x");
    const points_i = try expectIndexAccessNode(points_i_x.base);
    const user_points = try expectMemberAccess(points_i.base, "points");
    try expectNodeTag(user_points.base, .Identifier);
    try expectNodeTag(points_i.index, .Identifier);
    try expectNodeTag(mixed_assignment.value, .IntegerLiteral);
}

test "parser parses compound assignment statements as assignment nodes with compound operators" {
    const source =
        \\counter += 1;
        \\balance -= 3;
        \\numbers[i] *= 2;
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const first_assignment = try expectAssignment(&parsed.program.statements[0]);
    const second_assignment = try expectAssignment(&parsed.program.statements[1]);
    const third_assignment = try expectAssignment(&parsed.program.statements[2]);
    switch (first_assignment.operator) {
        .Compound => |binary_operator| try std.testing.expectEqual(ast.BinaryOperator.Add, binary_operator),
        else => return TestError.UnexpectedNodeKind,
    }
    try expectNodeTag(first_assignment.target, .Identifier);
    try expectNodeTag(first_assignment.value, .IntegerLiteral);
    switch (second_assignment.operator) {
        .Compound => |binary_operator| try std.testing.expectEqual(ast.BinaryOperator.Subtract, binary_operator),
        else => return TestError.UnexpectedNodeKind,
    }
    try expectNodeTag(second_assignment.target, .Identifier);
    try expectNodeTag(second_assignment.value, .IntegerLiteral);
    switch (third_assignment.operator) {
        .Compound => |binary_operator| try std.testing.expectEqual(ast.BinaryOperator.Multiply, binary_operator),
        else => return TestError.UnexpectedNodeKind,
    }
    const indexed_target = try expectIndexAccessNode(third_assignment.target);
    try expectNodeTag(indexed_target.base, .Identifier);
    try expectNodeTag(indexed_target.index, .Identifier);
    try expectNodeTag(third_assignment.value, .IntegerLiteral);
}

test "parser treats bare identifier match subjects as subjects, not structure construction" {
    const source =
        \\val message = match is_happy {
        \\    true => "yes",
        \\    false => "no",
        \\};
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const match_expression = try expectMatchExpressionNode(declaration.value);
    try std.testing.expect(match_expression.subject != null);
    try expectNodeTag(match_expression.subject.?, .Identifier);
    try std.testing.expectEqual(@as(usize, 2), match_expression.arms.len);
}

test "parser allows parenthesized structure construction as a match subject" {
    const source =
        \\val result = match (Point { x = 1, y = 2 }) {
        \\    else => 0,
        \\};
    ;

    var parsed = try parse(source);
    defer parsed.deinit();

    const declaration = try expectDeclarationNode(&parsed.program.statements[0]);
    const match_expression = try expectMatchExpressionNode(declaration.value);
    try std.testing.expect(match_expression.subject != null);
    try expectNodeTag(match_expression.subject.?, .StructureConstruction);
    try std.testing.expect(match_expression.else_arm != null);
}
