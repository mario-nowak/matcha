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
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.{ .primitive_operation = .add });
        }

        test "lowers integer division to a checked division" {
            const source =
                \\val quotient = 7 / 2;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.checked_divide);
        }

        test "lowers integer equality to a primitive operation" {
            const source =
                \\val same = 1 == 2;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.{ .primitive_operation = .equal });
        }

        test "lowers string addition to a runtime concatenation" {
            const source =
                \\val text = "a" + "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.string_concatenate);
        }

        test "lowers string equality to a runtime equality comparison" {
            const source =
                \\val same = "a" == "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.string_compare_equal);
        }

        test "lowers string inequality to a runtime inequality comparison" {
            const source =
                \\val different = "a" != "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.string_compare_not_equal);
        }

        test "lowers unit equality to a zero-sized equality comparison" {
            const source =
                \\val same = unit == unit;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.zero_sized_compare_equal);
        }

        test "lowers unit inequality to a zero-sized inequality comparison" {
            const source =
                \\val different = unit != unit;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.zero_sized_compare_not_equal);
        }

        test "lowers array equality to a primitive equality comparison" {
            const source =
                \\val same = [1] == [1];
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.{ .primitive_operation = .equal });
        }

        test "lowers and to a short-circuit operation" {
            const source =
                \\val both = true and false;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.short_circuit_and);
        }

        test "lowers or to a short-circuit operation" {
            const source =
                \\val either = true or false;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.BinaryOperationLowerer, &arena, source);
            const binary_expression = fixture.analyzed_program.resolved_program.program.modules[0].statements[0].kind.binding_declaration.value;

            const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(binary_expression.id).?).toMatch(.short_circuit_or);
        }
    };
};
