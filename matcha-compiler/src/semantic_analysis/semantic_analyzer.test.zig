const std = @import("std");
const helpers = @import("../test_helpers.zig");

const TestError = error{UnexpectedNodeKind};

fn expectAnalyzeError(expected: anyerror, source: []const u8) !void {
    var parsed = try helpers.parseProgram(source);
    defer parsed.deinit();

    const allocator = parsed.allocator();
    const name_resolver = @import("semantic_analysis").name_resolution.NameResolver.init(allocator);
    const type_checker = @import("semantic_analysis").type_checking.TypeChecker.init(allocator);
    const control_flow_validator = @import("semantic_analysis").control_flow_validation.ControlFlowValidator{};
    var analyzer = @import("semantic_analysis").SemanticAnalyzer.init(
        name_resolver,
        type_checker,
        control_flow_validator,
    );

    try std.testing.expectError(expected, analyzer.validateProgram(&parsed.program));
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
    const comparison_symbol_id = typed_program.resolved_program.name_resolution_map.get(parsed.program.statements[0].id).?;
    try std.testing.expectEqual(.Boolean, typed_program.symbol_type_map.get(comparison_symbol_id).?);
    try std.testing.expectEqual(.Boolean, typed_program.node_type_map.get(comparison_declaration.value.id).?);

    const unit_if_statement = switch (parsed.program.statements[1].kind) {
        .ExpressionStatement => |statement| statement,
        else => return TestError.UnexpectedNodeKind,
    };
    try std.testing.expectEqual(.Unit, typed_program.node_type_map.get(parsed.program.statements[1].id).?);
    try std.testing.expectEqual(.Unit, typed_program.node_type_map.get(unit_if_statement.expression.id).?);

    const score_declaration = switch (parsed.program.statements[2].kind) {
        .Declaration => |declaration| declaration,
        else => return TestError.UnexpectedNodeKind,
    };
    const score_symbol_id = typed_program.resolved_program.name_resolution_map.get(parsed.program.statements[2].id).?;
    try std.testing.expectEqual(.Integer, typed_program.symbol_type_map.get(score_symbol_id).?);
    try std.testing.expectEqual(.Integer, typed_program.node_type_map.get(score_declaration.value.id).?);
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

    const declaration_symbol = analyzed.typed_program.resolved_program.name_resolution_map.get(first_statement.id).?;
    const identifier_symbol = analyzed.typed_program.resolved_program.name_resolution_map.get(if_expression.condition.id).?;
    try std.testing.expectEqual(declaration_symbol, identifier_symbol);
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

test "semantic analysis rejects loop control outside loops" {
    try expectAnalyzeError(error.LeaveUsedOutsideOfLoop,
        \\if true { leave; }
    );

    try expectAnalyzeError(error.ContinueUsedOutsideOfLoop,
        \\if true { continue; }
    );
}
