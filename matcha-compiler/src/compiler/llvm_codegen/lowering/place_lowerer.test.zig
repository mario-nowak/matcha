const std = @import("std");
const ast = @import("ast");
const helpers = @import("../../test_helpers.zig");
const llvm_codegen = @import("llvm_codegen");
const PlaceLowerer = llvm_codegen.lowering.PlaceLowerer;

const TestError = helpers.TestError;

fn expectAssignment(node: *const ast.Node) TestError!ast.Assignment {
    return switch (node.kind) {
        .Assignment => |assignment| assignment,
        else => return TestError.UnexpectedNodeKind,
    };
}

test "place lowering records field element and binding targets" {
    const source =
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\point.x = 3;
        \\val numbers = [1, 2, 3];
        \\numbers[0] = 4;
        \\var counter = 0;
        \\counter += 1;
    ;
    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();
    var lowerer = PlaceLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const decisions = lowerer.lower(&analyzed.typed_program);
    const field_assignment = try expectAssignment(&analyzed.parsed.program.statements[2]);
    const field_assignment_target = field_assignment.target;
    const index_assignment = try expectAssignment(&analyzed.parsed.program.statements[4]);
    const index_assignment_target = index_assignment.target;
    const counter_assignment = try expectAssignment(&analyzed.parsed.program.statements[6]);
    const counter_assignment_target = counter_assignment.target;
    const counter_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[5].id).?;

    switch (decisions.get(field_assignment_target.id).?) {
        .StructureField => |structure_field| try std.testing.expectEqual(@as(u32, 0), structure_field.field_index),
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(index_assignment_target.id).?) {
        .ArrayElement => {},
        else => return TestError.UnexpectedNodeKind,
    }
    switch (decisions.get(counter_assignment_target.id).?) {
        .IdentifierBinding => |identifier_binding| try std.testing.expectEqual(counter_symbol_id, identifier_binding.symbol_id),
        else => return TestError.UnexpectedNodeKind,
    }
}
