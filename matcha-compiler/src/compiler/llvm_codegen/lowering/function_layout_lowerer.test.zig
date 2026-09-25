const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const FunctionLayoutLowerer = struct {
    pub const lower = struct {
        test "omits unit parameters from the parameter indices" {
            const source =
                \\item select(erased: unit, value: int): int = value;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.FunctionLayoutLowerer, &arena, source);
            const function_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(function_symbol_id).?).toMatch(.{ .parameter_index_kind_by_definition_index = .{
                .Absent,
                .{ .Index = 0 },
            } });
        }

        test "keeps a parameter of a structure with only unit fields" {
            const source =
                \\item Empty = structure { value: unit; };
                \\item keep(empty: Empty): int = 1;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.FunctionLayoutLowerer, &arena, source);
            const function_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[1].id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(function_symbol_id).?).toMatch(.{ .parameter_index_kind_by_definition_index = .{.{ .Index = 0 }} });
        }

        test "keeps the receiver of a structure method as the first parameter" {
            const source =
                \\item Point = structure {
                \\    x: int;
                \\
                \\    item shifted(self: Point, erased: unit, offset: int): int = offset;
                \\};
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.FunctionLayoutLowerer, &arena, source);
            const point_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
            const method_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(point_symbol_id).kind.Structure.function_symbol_ids[0];

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(method_symbol_id).?).toMatch(.{ .parameter_index_kind_by_definition_index = .{
                .{ .Index = 0 },
                .Absent,
                .{ .Index = 1 },
            } });
        }

        test "omits the return value when the function returns unit" {
            const source =
                \\item nothing(): unit = unit;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.FunctionLayoutLowerer, &arena, source);
            const function_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(function_symbol_id).?).toMatch(.{ .return_type_value_kind = .Absent });
        }

        test "keeps the return value of a structure with only unit fields" {
            const source =
                \\item Empty = structure { value: unit; };
                \\item make(): Empty = Empty { value = unit };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupLowererFixture(lowering.FunctionLayoutLowerer, &arena, source);
            const function_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[1].id).?;

            const layouts = fixture.lowerer.lower(fixture.analyzed_program);

            try expect(layouts.get(function_symbol_id).?).toMatch(.{ .return_type_value_kind = .Present });
        }
    };
};
