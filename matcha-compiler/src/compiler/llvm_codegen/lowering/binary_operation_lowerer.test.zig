const std = @import("std");
const helpers = @import("../../test_helpers.zig");
const llvm_codegen = @import("llvm_codegen");
const BinaryOperationLowerer = llvm_codegen.lowering.BinaryOperationLowerer;

const TestError = helpers.TestError;
const expectDeclarationNode = helpers.expectDeclarationNode;

test "binary operation lowering records primitive and runtime-backed strategies" {
    const source =
        \\val sum = 1 + 2;
        \\val text = "a" + "b";
        \\val same = text == "ab";
        \\val different = text != "c";
    ;
    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();
    var lowerer = BinaryOperationLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const decisions = lowerer.lower(&analyzed.typed_program);
    const sum_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[0]);
    const text_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[1]);
    const same_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[2]);
    const different_declaration = try expectDeclarationNode(&analyzed.parsed.program.statements[3]);

    switch (decisions.get(sum_declaration.value.id).?) {
        .PrimitiveOperation => |primitive_operation| try std.testing.expectEqual(.Add, primitive_operation),
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(text_declaration.value.id).?) {
        .StringConcatenate => {},
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(same_declaration.value.id).?) {
        .StringCompareEqual => {},
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(different_declaration.value.id).?) {
        .StringCompareNotEqual => {},
        else => return TestError.UnexpectedNodeKind,
    }
}
