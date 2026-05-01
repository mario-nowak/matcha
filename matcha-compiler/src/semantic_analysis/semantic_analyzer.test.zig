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

test "semantic analysis resolves array types in function signatures" {
    var analyzed = try helpers.analyzeProgram(
        \\item identity(values: int[]): int[] = values;
    );
    defer analyzed.deinit();

    const function_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(
        analyzed.parsed.program.statements[0].id,
    ).?;
    const resolved_function = switch (analyzed.typed_program.resolved_program.resolved_item_by_symbol_id.get(function_symbol_id).?) {
        .Function => |function| function,
        else => return TestError.UnexpectedNodeKind,
    };
    const expected_array_type = typing.Type{ .Array = analyzed.typed_program.type_store.integer_type_id };

    try expectType(
        expected_array_type,
        &analyzed.typed_program,
        analyzed.typed_program.type_by_symbol_id.get(function_symbol_id).?,
    );
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
        \\item Point = structure { x: int, y: int };
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

test "semantic analysis type-checks structure member access" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int, y: int };
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
        .StructureField => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
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
        .ArrayLength => {},
        else => return TestError.UnexpectedNodeKind,
    }
}

test "semantic analysis type-checks mutable structure field assignment" {
    var analyzed = try helpers.analyzeProgram(
        \\item Point = structure { x: int, y: int };
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

test "semantic analysis rejects invalid structure member access" {
    try expectAnalyzeError(error.TypeMismatch,
        \\val x = 1.x;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\item Point = structure { x: int, y: int };
        \\val point = Point { x = 1, y = 2 };
        \\val z = point.z;
    );
}

test "semantic analysis rejects immutable and mismatched structure field assignment" {
    try expectAnalyzeError(error.CannotAssignToImmutable,
        \\item Point = structure { x: int, y: int };
        \\val point = Point { x = 1, y = 2 };
        \\point.x = 3;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\item Point = structure { x: int, y: int };
        \\var point = Point { x = 1, y = 2 };
        \\point.x = false;
    );

    try expectAnalyzeError(error.TypeMismatch,
        \\var numbers = [1, 2, 3];
        \\numbers.length = 4;
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
