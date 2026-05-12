const std = @import("std");
const helpers = @import("../test_helpers.zig");
const ast = @import("ast");
const typing = @import("typing");

const TestError = error{UnexpectedNodeKind};

fn expectType(expected: typing.Type, typed_program: *const typing.TypedProgram, actual_type_id: typing.TypeId) !void {
    try std.testing.expectEqual(expected, typed_program.type_store.getType(actual_type_id));
}

fn expectAnalyzeError(expected: anyerror, source: []const u8) !void {
    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const allocator = parsed.allocator();
    const name_resolver = @import("semantic_analysis").name_resolution.NameResolver.init(allocator);
    const type_checker = @import("semantic_analysis").type_checking.TypeChecker.init(allocator);
    const control_flow_validator = @import("semantic_analysis").control_flow_validation.ControlFlowValidator.init(allocator);
    var analyzer = @import("semantic_analysis").SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
    );

    try std.testing.expectError(expected, analyzer.validateProgram(&parsed.program));
}

fn expectFunctionItem(node: *const ast.Node) !ast.Function {
    const item_definition = switch (node.kind) {
        .ItemDefinition => |item| item,
        else => return TestError.UnexpectedNodeKind,
    };
    return switch (item_definition.item) {
        .Function => |definition| definition,
        else => return TestError.UnexpectedNodeKind,
    };
}

test "semantic analysis assigns expected types to if forms and comparisons" {
    const source =
        \\val comparison = 5 >= 3;
        \\if comparison { val left = 1; } else { val right = 2; };
        \\val score = if comparison { 1 } else { 0 };
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    const parsed = analyzed.parsed;
    const typed_program = analyzed.typed_program;

    const comparison_declaration = switch (parsed.program.statements[0].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const comparison_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(parsed.program.statements[0].id).?;
    try expectType(.Boolean, &typed_program, typed_program.type_by_symbol_id.get(comparison_symbol_id).?);
    try expectType(.Boolean, &typed_program, typed_program.type_by_node_id.get(comparison_declaration.value.id).?);

    const unit_if_statement = switch (parsed.program.statements[1].kind) {
        .ExpressionStatement => |statement| statement,
        else => return TestError.UnexpectedNodeKind,
    };
    try expectType(.Unit, &typed_program, typed_program.type_by_node_id.get(parsed.program.statements[1].id).?);
    try expectType(.Unit, &typed_program, typed_program.type_by_node_id.get(unit_if_statement.expression.id).?);

    const score_declaration = switch (parsed.program.statements[2].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const score_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(parsed.program.statements[2].id).?;
    try expectType(.Integer, &typed_program, typed_program.type_by_symbol_id.get(score_symbol_id).?);
    try expectType(.Integer, &typed_program, typed_program.type_by_node_id.get(score_declaration.value.id).?);
}

test "semantic analysis maps declaration and identifier use to the same symbol" {
    const source =
        \\val flag = true;
        \\val answer = if flag { 1 } else { 0 };
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    const first_statement = analyzed.parsed.program.statements[0];
    const second_declaration = switch (analyzed.parsed.program.statements[1].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const if_expression = switch (second_declaration.value.kind) {
        .IfExpression => |expression| expression,
        else => return TestError.UnexpectedNodeKind,
    };

    const declaration_symbol = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(first_statement.id).?;
    const identifier_symbol = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(if_expression.condition.id).?;
    try std.testing.expectEqual(declaration_symbol, identifier_symbol);
}

test "semantic analysis resolves parameter references inside function bodies" {
    var analyzed = try helpers.analyzeProgram(
        \\item identity(value: int): int = value;
    );
    defer analyzed.deinit();

    const function_definition = try expectFunctionItem(&analyzed.parsed.program.statements[0]);

    try expectType(
        .Integer,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_node_id.get(function_definition.body_expression.id).?,
    );
}

test "semantic analysis allows if expression as expression-bodied function body" {
    var analyzed = try helpers.analyzeProgram(
        \\item choose(flag: boolean): int = if flag { 1 } else { 0 };
    );
    defer analyzed.deinit();

    const function_definition = try expectFunctionItem(&analyzed.parsed.program.statements[0]);

    try expectType(
        .Integer,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_node_id.get(function_definition.body_expression.id).?,
    );
}

test "semantic analysis allows match expression as expression-bodied function body" {
    var analyzed = try helpers.analyzeProgram(
        \\item choose(value: int): int = match value {
        \\    0 => 1,
        \\    else => value,
        \\};
    );
    defer analyzed.deinit();

    const function_definition = try expectFunctionItem(&analyzed.parsed.program.statements[0]);

    try expectType(
        .Integer,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_node_id.get(function_definition.body_expression.id).?,
    );
}

test "semantic analysis rejects non-boolean if conditions" {
    try expectAnalyzeError(error.TypeMismatch,
        \\if 1 { val x = 1; }
    );
}

test "semantic analysis rejects non-boolean while conditions" {
    try expectAnalyzeError(error.TypeMismatch,
        \\while 1 {
        \\    leave;
        \\}
    );
}

test "semantic analysis rejects mismatched if expression branches" {
    try expectAnalyzeError(error.TypeMismatch,
        \\val value = if true { 1 } else { false };
    );
}

test "semantic analysis rejects non-unit if expressions used as statements" {
    try expectAnalyzeError(error.BlockCannotProduceValue,
        \\if true { 1 } else { 2 };
    );
}

test "semantic analysis rejects unary not on integers" {
    try expectAnalyzeError(error.TypeMismatch,
        \\val bad = not 1;
    );
}

test "semantic analysis rejects non-unit expression-bodied functions with a branch that falls through without a value" {
    try expectAnalyzeError(error.NotAllPathsReturnValue,
        \\item f(): int = if true { 1 } else { val x = 1; };
    );
}

test "semantic analysis rejects loop control outside loops" {
    try expectAnalyzeError(error.LeaveUsedOutsideOfLoop,
        \\if true { leave; }
    );

    try expectAnalyzeError(error.ContinueUsedOutsideOfLoop,
        \\if true { continue; }
    );
}

test "semantic analysis infers string type for string literals" {
    var analyzed = try helpers.analyzeProgram(
        \\val greeting = "hello";
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[0].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
}

test "semantic analysis resolves string type annotation" {
    var analyzed = try helpers.analyzeProgram(
        \\val greeting: string = "hello";
    );
    defer analyzed.deinit();

    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
}

test "semantic analysis type-checks readFile builtin" {
    var analyzed = try helpers.analyzeProgram(
        \\val input = readFile("input.txt");
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[0].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
}

test "semantic analysis type-checks readLine builtin" {
    var analyzed = try helpers.analyzeProgram(
        \\val line = readLine();
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[0].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
}

test "semantic analysis type-checks getArguments builtin" {
    var analyzed = try helpers.analyzeProgram(
        \\val args = getArguments();
        \\val count = args.length;
        \\val first = args[0];
    );
    defer analyzed.deinit();

    const args_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    try expectType(
        .{ .Array = analyzed.typed_program.type_store.string_type_id },
        &analyzed.typed_program,
        analyzed.typed_program.type_by_symbol_id.get(args_symbol_id).?,
    );

    const count_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[1].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(count_symbol_id).?);

    const first_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[2].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(first_symbol_id).?);
}

test "semantic analysis type-checks string length and parsing helpers" {
    var analyzed = try helpers.analyzeProgram(
        \\val input = " 1,2 ";
        \\val trimmed = input.trim();
        \\val lines = trimmed.split(",");
        \\val first = lines[0].toInt();
        \\val length = trimmed.length;
    );
    defer analyzed.deinit();

    const trimmed_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[1].id).?;
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(trimmed_symbol_id).?);

    const lines_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[2].id).?;
    try expectType(
        .{ .Array = analyzed.typed_program.type_store.string_type_id },
        &analyzed.typed_program,
        analyzed.typed_program.type_by_symbol_id.get(lines_symbol_id).?,
    );

    const first_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[3].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(first_symbol_id).?);

    const length_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[4].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(length_symbol_id).?);
}

test "semantic analysis resolves array types in function signatures" {
    var analyzed = try helpers.analyzeProgram(
        \\item identity(values: int[]): int[] = values;
    );
    defer analyzed.deinit();

    const function_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[0].id,
    ).?;
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

test "semantic analysis type-checks printString with string argument" {
    var analyzed = try helpers.analyzeProgram(
        \\printString("hello");
    );
    defer analyzed.deinit();
}

test "semantic analysis rejects printString with integer argument" {
    try expectAnalyzeError(error.TypeMismatch,
        \\printString(42);
    );
}

test "semantic analysis type-checks string-typed function definitions" {
    var analyzed = try helpers.analyzeProgram(
        \\item echo(x: string): string = x;
    );
    defer analyzed.deinit();

    const function_definition = try expectFunctionItem(&analyzed.parsed.program.statements[0]);
    try expectType(
        .String,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_node_id.get(function_definition.body_expression.id).?,
    );
}

test "semantic analysis rejects assigning integer to string variable" {
    try expectAnalyzeError(error.TypeMismatch,
        \\val greeting: string = 42;
    );
}

test "semantic analysis type-checks exhaustive boolean match expressions" {
    var analyzed = try helpers.analyzeProgram(
        \\val label = match true {
        \\    true => "yes",
        \\    false => "no",
        \\};
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[0].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    try expectType(.String, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
}

test "semantic analysis type-checks subjectless and integer matches with else" {
    var analyzed = try helpers.analyzeProgram(
        \\val a = match {
        \\    true => 1,
        \\    else => 0,
        \\};
        \\val b = match 2 {
        \\    1 + 1 => "one",
        \\    else => "other",
        \\};
    );
    defer analyzed.deinit();
}

test "semantic analysis records structure construction layout in source order" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { y = 2, x = 1 };
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[1].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const structure_construction = switch (declaration.value.kind) {
        .StructureConstruction => |construction| construction,
        else => return TestError.UnexpectedNodeKind,
    };
    _ = structure_construction;

    const construction_layout = analyzed.typed_program.structure_construction_layout_by_node_id.get(declaration.value.id).?;
    try std.testing.expectEqual(@as(usize, 2), construction_layout.field_indices.len);
    try std.testing.expectEqual(@as(u32, 1), construction_layout.field_indices[0]);
    try std.testing.expectEqual(@as(u32, 0), construction_layout.field_indices[1]);
}

test "semantic analysis type-checks anonymous structure literals from contextual type" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\val point: Point = .{ y = 2, x = 1 };
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[1].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const anonymous_structure_literal = switch (declaration.value.kind) {
        .AnonymousStructureLiteral => |literal| literal,
        else => return TestError.UnexpectedNodeKind,
    };
    _ = anonymous_structure_literal;

    const construction_layout = analyzed.typed_program.structure_construction_layout_by_node_id.get(declaration.value.id).?;
    try std.testing.expectEqual(@as(usize, 2), construction_layout.field_indices.len);
    try std.testing.expectEqual(@as(u32, 1), construction_layout.field_indices[0]);
    try std.testing.expectEqual(@as(u32, 0), construction_layout.field_indices[1]);
}

test "semantic analysis rejects anonymous structure literals without contextual type" {
    try expectAnalyzeError(error.CannotInferType,
        \\item Point = structure { x: int; y: int; };
        \\val point = .{ x = 1, y = 2 };
    );
}

test "semantic analysis threads contextual type through function body and branch expressions" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\
        \\item viaBlockResult(): Point = {
        \\    .{ x = 1, y = 2 }
        \\};
        \\
        \\item viaIfExpression(flag: boolean): Point = if flag {
        \\    .{ x = 3, y = 4 }
        \\} else {
        \\    .{ x = 5, y = 6 }
        \\};
        \\
        \\item viaMatchExpression(code: int): Point = match code {
        \\    0 => .{ x = 7, y = 8 },
        \\    else => .{ x = 9, y = 10 },
        \\};
        \\
        \\item viaReturn(flag: boolean): Point = {
        \\    if flag {
        \\        return .{ x = 11, y = 12 };
        \\    }
        \\    return .{ x = 13, y = 14 };
        \\};
    );
    defer analyzed.deinit();
}

test "semantic analysis type-checks structure member access" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\val x = point.x;
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[2].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[2].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(declaration.value.id).?;
    switch (member_access) {
        .StructureInstanceFieldAccess => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis type-checks structure function calls" {
    var analyzed = try helpers.analyzeProgram(
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
    );
    defer analyzed.deinit();

    const point_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[0].id,
    ).?;
    const point_type_id = analyzed.typed_program.type_by_symbol_id.get(point_symbol_id).?;
    const moved_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[3].id,
    ).?;
    try std.testing.expectEqual(point_type_id, analyzed.typed_program.type_by_symbol_id.get(moved_symbol_id).?);

    const moved_declaration = switch (analyzed.parsed.program.statements[3].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const call_expression = switch (moved_declaration.value.kind) {
        .CallExpression => |call_expression| call_expression,
        else => return TestError.UnexpectedNodeKind,
    };
    const member_access = analyzed.typed_program.member_access_by_node_id.get(call_expression.callee.id).?;
    switch (member_access) {
        .StructureTypeFunctionAccess => |structure_function| {
            try std.testing.expectEqual(point_symbol_id, structure_function.structure_symbol_id);
        },
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis type-checks structure instance method calls" {
    var analyzed = try helpers.analyzeProgram(
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
    );
    defer analyzed.deinit();

    const moved_declaration = switch (analyzed.parsed.program.statements[3].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const moved_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[3].id,
    ).?;
    const point_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[0].id,
    ).?;
    try std.testing.expectEqual(
        analyzed.typed_program.type_by_symbol_id.get(point_symbol_id).?,
        analyzed.typed_program.type_by_symbol_id.get(moved_symbol_id).?,
    );

    const call_expression = switch (moved_declaration.value.kind) {
        .CallExpression => |call_expression| call_expression,
        else => return TestError.UnexpectedNodeKind,
    };
    const method_access = analyzed.typed_program.member_access_by_node_id.get(call_expression.callee.id).?;
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

test "semantic analysis type-checks array length member access" {
    var analyzed = try helpers.analyzeProgram(
        \\val numbers = [1, 2, 3];
        \\val length = numbers.length;
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[1].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    const symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[1].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(symbol_id).?);
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
    const member_access = analyzed.typed_program.member_access_by_node_id.get(declaration.value.id).?;
    switch (member_access) {
        .ArrayInstanceFieldAccess => |array_field| try std.testing.expectEqual(@as(typing.ArrayInstanceField, .Length), array_field),
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis type-checks array append instance method calls" {
    var analyzed = try helpers.analyzeProgram(
        \\val numbers = [1, 2, 3];
        \\numbers.append(4);
        \\val length = numbers.length;
    );
    defer analyzed.deinit();

    const append_expression_statement = switch (analyzed.parsed.program.statements[1].kind) {
        .ExpressionStatement => |expression_statement| expression_statement,
        else => return TestError.UnexpectedNodeKind,
    };
    const append_call = switch (append_expression_statement.expression.kind) {
        .CallExpression => |call_expression| call_expression,
        else => return TestError.UnexpectedNodeKind,
    };
    const member_access = analyzed.typed_program.member_access_by_node_id.get(append_call.callee.id).?;
    switch (member_access) {
        .ArrayInstanceMethodAccess => |array_method| try std.testing.expectEqual(@as(@TypeOf(array_method), .Append), array_method),
        else => return TestError.UnexpectedNodeKind,
    }

    const length_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[2].id).?;
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_symbol_id.get(length_symbol_id).?);
}

test "semantic analysis type-checks mutable structure field assignment" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\point.x = 3;
        \\val x = point.x;
    );
    defer analyzed.deinit();

    const declaration = switch (analyzed.parsed.program.statements[3].kind) {
        .Declaration => |d| d,
        else => return TestError.UnexpectedNodeKind,
    };
    try expectType(.Integer, &analyzed.typed_program, analyzed.typed_program.type_by_node_id.get(declaration.value.id).?);
}

test "semantic analysis type-checks compound assignments" {
    var analyzed = try helpers.analyzeProgram(
        \\var counter = 1;
        \\counter += 2;
        \\counter -= 1;
        \\var numbers = [1, 2, 3];
        \\numbers[0] *= 4;
    );
    defer analyzed.deinit();
}

test "semantic analysis rejects invalid structure member access" {
    try expectAnalyzeError(error.TypeMismatch,
        \\val x = 1.x;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\val z = point.z;
    );
}

test "semantic analysis allows member and indexed assignment through val bindings" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\point.x = 3;
        \\val numbers = [1, 2, 3];
        \\numbers[0] = 4;
    );
    defer analyzed.deinit();
}

test "semantic analysis rejects rebinding of immutable bindings" {
    try expectAnalyzeError(error.CannotAssignToImmutable,
        \\val answer = 1;
        \\answer = 2;
    );
}

test "semantic analysis rejects mismatched and read-only place assignment" {
    try expectAnalyzeError(error.TypeMismatch,
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\point.x = false;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\var numbers = [1, 2, 3];
        \\numbers.length = 4;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\var flag = true;
        \\flag += 1;
    );
}

test "semantic analysis rejects non-exhaustive boolean and integer matches without else" {
    try expectAnalyzeError(error.NonExhaustiveMatch,
        \\val label = match true {
        \\    true => "yes",
        \\};
    );

    try expectAnalyzeError(error.NonExhaustiveMatch,
        \\val label = match 1 {
        \\    1 => "one",
        \\};
    );
}

test "semantic analysis rejects duplicate and invalid v1 match arms" {
    try expectAnalyzeError(error.DuplicateMatchArm,
        \\val label = match true {
        \\    true => "yes",
        \\    true => "still yes",
        \\    false => "no",
        \\};
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\val label = match 1 {
        \\    "two" => "two",
        \\    else => "other",
        \\};
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\val label = match {
        \\    1 => "one",
        \\    else => "other",
        \\};
    );
}

test "semantic analysis only allows statement-position match when it evaluates to unit" {
    var analyzed = try helpers.analyzeProgram(
        \\match true {
        \\    true => printInt(1),
        \\    false => printInt(0),
        \\};
    );
    defer analyzed.deinit();

    try expectAnalyzeError(error.BlockCannotProduceValue,
        \\match true {
        \\    true => 1,
        \\    false => 0,
        \\};
    );
}
