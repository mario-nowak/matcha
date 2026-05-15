const std = @import("std");
const ast = @import("ast");
const helpers = @import("../test_helpers.zig");
const typing = @import("typing");

const TestError = helpers.TestError;

const expectDeclarationNode = helpers.expectDeclarationNode;
const expectFunctionItem = helpers.expectFunctionItem;
const expectCallExpressionNode = helpers.expectCallExpressionNode;

fn analyze(source: []const u8) !helpers.AnalyzedProgram {
    return helpers.analyzeProgram(source);
}

fn expectType(expected: typing.Type, typed_program: *const typing.TypedProgram, actual_type_id: typing.TypeId) !void {
    try std.testing.expectEqual(expected, typed_program.type_store.getType(actual_type_id));
}

fn expectStatementSymbolId(analyzed: *const helpers.AnalyzedProgram, statement_index: usize) typing.SymbolId {
    return analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[statement_index].id).?;
}

test "semantic analysis maps declaration and identifier use to the same symbol" {
    const source =
        \\val flag = true;
        \\val answer = if flag { 1 } else { 0 };
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const declaration_symbol = expectStatementSymbolId(&analyzed, 0);
    const answer_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    const if_expression = switch (answer_declaration.value.kind) {
        .IfExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };
    const identifier_symbol = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(if_expression.condition.id).?;
    try std.testing.expectEqual(declaration_symbol, identifier_symbol);
}

test "semantic analysis resolves parameter references inside function bodies" {
    const source =
        \\item identity(value: int): int = value;
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const function_definition = try expectFunctionItem(&analyzed.parsed.program.statements[0]);
    try expectType(
        .Integer,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_node_id.get(function_definition.body_expression.id).?,
    );
}

test "semantic analysis resolves array types in function signatures" {
    const source =
        \\item identity(values: int[]): int[] = values;
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const function_symbol_id = expectStatementSymbolId(&analyzed, 0);
    const resolved_function = analyzed.typed_program.resolved_program.resolved_function_by_symbol_id.get(function_symbol_id).?;
    const expected_array_type = typing.Type{ .Array = analyzed.typed_program.type_store.integer_type_id };
    const function_type_id = analyzed.typed_program.type_by_symbol_id.get(function_symbol_id).?;
    const function_type = switch (analyzed.typed_program.type_store.getType(function_type_id)) {
        .Function => |id| analyzed.typed_program.type_store.function_types.items[id],
        else => return TestError.UnexpectedNodeKind,
    };
    try expectType(expected_array_type, &analyzed.typed_program, function_type.return_type);
    try expectType(
        expected_array_type,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_symbol_id.get(resolved_function.parameters[0].symbol_id).?,
    );
}

test "semantic analysis records structure construction layout in source order" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { y = 2, x = 1 };
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    const construction_layout = analyzed.typed_program.structure_construction_layout_by_node_id.get(declaration.value.id).?;
    try std.testing.expectEqual(@as(usize, 2), construction_layout.field_indices.len);
    try std.testing.expectEqual(@as(u32, 1), construction_layout.field_indices[0]);
    try std.testing.expectEqual(@as(u32, 0), construction_layout.field_indices[1]);
}

test "semantic analysis records anonymous structure literal layout from contextual type" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point: Point = .{ y = 2, x = 1 };
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    const construction_layout = analyzed.typed_program.structure_construction_layout_by_node_id.get(declaration.value.id).?;
    try std.testing.expectEqual(@as(usize, 2), construction_layout.field_indices.len);
    try std.testing.expectEqual(@as(u32, 1), construction_layout.field_indices[0]);
    try std.testing.expectEqual(@as(u32, 0), construction_layout.field_indices[1]);
}

test "semantic analysis records structure member access metadata" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\val x = point.x;
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    const symbol_id = expectStatementSymbolId(&analyzed, 2);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(declaration.value.id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
    switch (member_access) {
        .StructureInstanceFieldAccess => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis records structure type function access metadata" {
    const source =
        \\item Point = structure {
        \\    x: int;
        \\    y: int;
        \\
        \\    item movedBy(self: Point, other: Point): Point = Point {
        \\        x = self.x + other.x,
        \\        y = self.y + other.y,
        \\    };
        \\};
        \\val point = Point { x = 1, y = 2 };
        \\val other = Point { x = 3, y = 4 };
        \\val moved = Point.movedBy(point, other);
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const point_symbol_id = expectStatementSymbolId(&analyzed, 0);
    const moved_symbol_id = expectStatementSymbolId(&analyzed, 3);
    const moved_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);
    const call_expression = try expectCallExpressionNode(moved_declaration.value);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(call_expression.callee.id).?;
    try std.testing.expectEqual(
        analyzed.typed_program.type_by_symbol_id.get(point_symbol_id).?,
        analyzed.typed_program.type_by_symbol_id.get(moved_symbol_id).?,
    );
    switch (member_access) {
        .StructureTypeFunctionAccess => |structure_function| {
            try std.testing.expectEqual(point_symbol_id, structure_function.structure_symbol_id);
        },
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis records structure instance method access metadata" {
    const source =
        \\item Point = structure {
        \\    x: int;
        \\    y: int;
        \\
        \\    item movedBy(self: Point, other: Point): Point = Point {
        \\        x = self.x + other.x,
        \\        y = self.y + other.y,
        \\    };
        \\};
        \\val point = Point { x = 1, y = 2 };
        \\val other = Point { x = 3, y = 4 };
        \\val moved = point.movedBy(other);
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const point_symbol_id = expectStatementSymbolId(&analyzed, 0);
    const moved_symbol_id = expectStatementSymbolId(&analyzed, 3);
    const moved_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);
    const call_expression = try expectCallExpressionNode(moved_declaration.value);
    const method_access = analyzed.typed_program.member_access_by_node_id.get(call_expression.callee.id).?;
    try std.testing.expectEqual(
        analyzed.typed_program.type_by_symbol_id.get(point_symbol_id).?,
        analyzed.typed_program.type_by_symbol_id.get(moved_symbol_id).?,
    );
    switch (method_access) {
        .StructureInstanceMethodAccess => |structure_method| {
            const method_function_type_id = analyzed.typed_program.type_by_node_id.get(call_expression.callee.id).?;
            const method_function_type = switch (analyzed.typed_program.type_store.getType(method_function_type_id)) {
                .Function => |id| analyzed.typed_program.type_store.function_types.items[id],
                else => return TestError.UnexpectedNodeKind,
            };
            try std.testing.expectEqual(@as(usize, 1), method_function_type.parameter_types.len);
            try std.testing.expectEqualStrings("movedBy", analyzed.typed_program.resolved_program.symbol_table.getSymbol(structure_method.function_symbol_id).name);
        },
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis records array length member access metadata" {
    const source =
        \\val numbers = [1, 2, 3];
        \\val length = numbers.length;
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    const symbol_id = expectStatementSymbolId(&analyzed, 1);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(declaration.value.id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
    switch (member_access) {
        .ArrayInstanceFieldAccess => |array_field| try std.testing.expectEqual(@as(typing.ArrayInstanceField, .Length), array_field),
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis records array append instance method access metadata" {
    const source =
        \\val numbers = [1, 2, 3];
        \\numbers.append(4);
        \\val length = numbers.length;
    ;

    var analyzed = try analyze(source);
    defer analyzed.deinit();

    const append_statement = switch (analyzed.parsed.program.statements[1].kind) {
        .ExpressionStatement => |expression_statement| expression_statement,
        else => return TestError.UnexpectedNodeKind,
    };
    const append_call = try expectCallExpressionNode(append_statement.expression);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(append_call.callee.id).?;
    const length_symbol_id = expectStatementSymbolId(&analyzed, 2);
    switch (member_access) {
        .ArrayInstanceMethodAccess => |array_method| try std.testing.expectEqual(@as(@TypeOf(array_method), .Append), array_method),
        else => return TestError.UnexpectedNodeKind,
    }
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(length_symbol_id).?);
}
