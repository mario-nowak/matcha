const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const BinaryOperationLowerer = struct {
    pub const lower = struct {
        test "lowers integer addition to a primitive operation" {
            const source =
                \\val sum = 1 + 2;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.{ .PrimitiveOperation = .Add });
        }

        test "lowers integer equality to a primitive operation" {
            const source =
                \\val same = 1 == 2;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.{ .PrimitiveOperation = .Equal });
        }

        test "lowers string addition to a runtime concatenation" {
            const source =
                \\val text = "a" + "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.StringConcatenate);
        }

        test "lowers string equality to a runtime equality comparison" {
            const source =
                \\val same = "a" == "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.StringCompareEqual);
        }

        test "lowers string inequality to a runtime inequality comparison" {
            const source =
                \\val different = "a" != "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.BindingDeclaration.value;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.StringCompareNotEqual);
        }
    };
};
