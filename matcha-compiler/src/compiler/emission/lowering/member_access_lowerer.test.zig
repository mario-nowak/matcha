const std = @import("std");
const helpers = @import("../../test_helpers.zig");
const emission = @import("emission");
const MemberAccessLowerer = emission.lowering.MemberAccessLowerer;

const TestError = helpers.TestError;
const expectDeclarationNode = helpers.expectDeclarationNode;

test "member access lowering records field and synthetic field targets" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\val field = point.x;
        \\val text = "hello";
        \\val text_length = text.length;
        \\val numbers = [1, 2, 3];
        \\val array_length = numbers.length;
    ;
    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();
    var lowerer = MemberAccessLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const decisions = lowerer.lower(&analyzed.typed_program);
    const field_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    const text_length_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[4]);
    const array_length_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[6]);

    switch (decisions.get(field_declaration.value.id).?) {
        .StructureField => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(text_length_declaration.value.id).?) {
        .StringLength => {},
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(array_length_declaration.value.id).?) {
        .ArrayLength => {},
        else => return TestError.UnexpectedNodeKind,
    }
}
