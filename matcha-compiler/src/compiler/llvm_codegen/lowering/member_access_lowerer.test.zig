const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const MemberAccessLowerer = struct {
    pub const lower = struct {
        test "lowers a structure field access to its field index" {
            const source =
                \\item Point = structure { x: int; y: int; };
                \\val point = Point { x = 1, y = 2 };
                \\val y = point.y;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.MemberAccessLowerer, &arena, source);
            const member_expression = fixture.analyzed_program.resolved_program.program.statements[2].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(member_expression.id).?).toMatch(.{ .StructureField = .{ .field_index = 1 } });
        }

        test "lowers the length of a string to a string length access" {
            const source =
                \\val text = "hello";
                \\val length = text.length;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.MemberAccessLowerer, &arena, source);
            const member_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(member_expression.id).?).toMatch(.StringLength);
        }

        test "lowers the length of an array to an array length access" {
            const source =
                \\val numbers = [1, 2];
                \\val length = numbers.length;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.MemberAccessLowerer, &arena, source);
            const member_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(member_expression.id).?).toMatch(.ArrayLength);
        }
    };
};
