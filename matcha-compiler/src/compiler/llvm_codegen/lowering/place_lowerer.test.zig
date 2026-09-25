const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const PlaceLowerer = struct {
    pub const lower = struct {
        test "lowers a structure field target to its field index" {
            const source =
                \\item Point = structure { x: int; y: int; };
                \\var point = Point { x = 1, y = 2 };
                \\point.y = 3;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.PlaceLowerer, &arena, source);
            const assignment_target = fixture.analyzed_program.resolved_program.program.statements[2].kind.AssignmentStatement.target;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(assignment_target.id).?).toMatch(.{ .StructureField = .{ .field_index = 1 } });
        }

        test "lowers an indexed target to an array element" {
            const source =
                \\val numbers = [1];
                \\numbers[0] = 2;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.PlaceLowerer, &arena, source);
            const assignment_target = fixture.analyzed_program.resolved_program.program.statements[1].kind.AssignmentStatement.target;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(assignment_target.id).?).toMatch(.ArrayElement);
        }

        test "lowers a variable target to its binding" {
            const source =
                \\var counter = 0;
                \\counter = 1;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.PlaceLowerer, &arena, source);
            const counter_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
            const assignment_target = fixture.analyzed_program.resolved_program.program.statements[1].kind.AssignmentStatement.target;

            const decisions = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(decisions.get(assignment_target.id).?).toMatch(.{ .IdentifierBinding = .{ .symbol_id = counter_symbol_id } });
        }
    };
};
