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
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.modules[0].statements[0].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.{ .present = .{ .field_index_kind_by_definition_index = .{
                .{ .index = 0 },
                .absent,
                .{ .index = 1 },
            } } });
        }

        test "names the llvm type after the structure name" {
            const source =
                \\item Point = structure { x: int; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.modules[0].statements[0].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.{ .present = .{ .llvm_type_name = "matcha.structure.Point" } });
        }

        test "keeps a field of a structure with only unit fields" {
            const source =
                \\item Empty = structure { value: unit; };
                \\item Outer = structure { empty: Empty; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.modules[0].statements[1].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.{ .present = .{ .field_index_kind_by_definition_index = .{.{ .index = 0 }} } });
        }

        test "gives a structure with only unit fields no layout" {
            const source =
                \\item Empty = structure { first: unit; second: unit; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.StructureLayoutLowerer, &arena, source);
            const structure_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.modules[0].statements[0].id).?;
            const structure_type_id = fixture.analyzed_program.type_id_by_symbol_id.get(structure_symbol_id).?;

            const layouts = try fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(structure_type_id).?).toMatch(.absent);
        }
    };
};
