const std = @import("std");
const ast = @import("ast");
const helpers = @import("../test_helpers.zig");
const emission = @import("emission");

const TestError = helpers.TestError;
const expectDeclarationNode = helpers.expectDeclarationNode;

fn expectExpressionStatement(node: *const ast.Node) TestError!ast.ExpressionStatement {
    return switch (node.kind) {
        .ExpressionStatement => |expression_statement| expression_statement,
        else => return TestError.UnexpectedNodeKind,
    };
}

test "member access and place lowering record field synthetic field and place targets" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\val field = point.x;
        \\point.x = 3;
        \\val text = "hello";
        \\val text_length = text.length;
        \\val numbers = [1, 2, 3];
        \\numbers[0] = 4;
        \\var counter = 0;
        \\counter += 1;
        \\val array_length = numbers.length;
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    var member_access_lowerer = emission.lowering.MemberAccessLowerer.init(std.testing.allocator);
    defer member_access_lowerer.deinit();
    var place_lowerer = emission.lowering.PlaceLowerer.init(std.testing.allocator);
    defer place_lowerer.deinit();

    const member_access_decisions = member_access_lowerer.lower(&analyzed.typed_program);
    const place_decisions = place_lowerer.lower(&analyzed.typed_program);

    const field_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    switch (member_access_decisions.get(field_declaration.value.id).?) {
        .StructureField => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }

    const field_assignment = try expectExpressionStatement(&analyzed.parsed.program.statements[3]);
    const field_assignment_target = switch (field_assignment.expression.kind) {
        .Assignment => |assignment| assignment.target,
        else => return TestError.UnexpectedNodeKind,
    };
    switch (place_decisions.get(field_assignment_target.id).?) {
        .StructureField => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }

    const text_length_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[5]);
    switch (member_access_decisions.get(text_length_declaration.value.id).?) {
        .StringLength => {},
        else => return TestError.UnexpectedNodeKind,
    }

    const index_assignment = try expectExpressionStatement(&analyzed.parsed.program.statements[7]);
    const index_assignment_target = switch (index_assignment.expression.kind) {
        .Assignment => |assignment| assignment.target,
        else => return TestError.UnexpectedNodeKind,
    };
    switch (place_decisions.get(index_assignment_target.id).?) {
        .ArrayElement => {},
        else => return TestError.UnexpectedNodeKind,
    }

    const counter_assignment = try expectExpressionStatement(&analyzed.parsed.program.statements[9]);
    const counter_assignment_target = switch (counter_assignment.expression.kind) {
        .Assignment => |assignment| assignment.target,
        else => return TestError.UnexpectedNodeKind,
    };
    const counter_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[8].id).?;
    switch (place_decisions.get(counter_assignment_target.id).?) {
        .IdentifierBinding => |identifier_binding| try std.testing.expectEqual(counter_symbol_id, identifier_binding.symbol_id),
        else => return TestError.UnexpectedNodeKind,
    }

    const array_length_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[10]);
    switch (member_access_decisions.get(array_length_declaration.value.id).?) {
        .ArrayLength => {},
        else => return TestError.UnexpectedNodeKind,
    }
}

test "binary operation lowering records primitive and runtime-backed strategies" {
    const source =
        \\val sum = 1 + 2;
        \\val text = "a" + "b";
        \\val same = text == "ab";
        \\val different = text != "c";
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    var binary_operation_lowerer = emission.lowering.BinaryOperationLowerer.init(std.testing.allocator);
    defer binary_operation_lowerer.deinit();

    const binary_operation_decisions = binary_operation_lowerer.lower(&analyzed.typed_program);

    const sum_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[0]);
    switch (binary_operation_decisions.get(sum_declaration.value.id).?) {
        .PrimitiveOperation => |primitive_operation| try std.testing.expectEqual(.Add, primitive_operation),
        else => return TestError.UnexpectedNodeKind,
    }

    const text_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    switch (binary_operation_decisions.get(text_declaration.value.id).?) {
        .StringConcatenate => {},
        else => return TestError.UnexpectedNodeKind,
    }

    const same_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    switch (binary_operation_decisions.get(same_declaration.value.id).?) {
        .StringCompareEqual => {},
        else => return TestError.UnexpectedNodeKind,
    }

    const different_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);
    switch (binary_operation_decisions.get(different_declaration.value.id).?) {
        .StringCompareNotEqual => {},
        else => return TestError.UnexpectedNodeKind,
    }
}
