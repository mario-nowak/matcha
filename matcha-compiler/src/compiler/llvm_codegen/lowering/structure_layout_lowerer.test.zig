const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const StructureLayoutLowerer = struct {
    pub const lower = struct {
        test "omits unit fields from the field indices" {
            const source =
                \\item Mixed = structure { first: int; erased: unit; last: string; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.{ .Present = .{ .field_index_kind_by_definition_index = .{
                .{ .Index = 0 },
                .Absent,
                .{ .Index = 1 },
            } } });
        }

        test "keeps a field of a structure with only unit fields" {
            const source =
                \\item Empty = structure { value: unit; };
                \\item Outer = structure { empty: Empty; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[1].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.{ .Present = .{ .field_index_kind_by_definition_index = .{.{ .Index = 0 }} } });
        }

        test "gives a structure with only unit fields no layout" {
            const source =
                \\item Empty = structure { first: unit; second: unit; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.Absent);
        }
    };
};
