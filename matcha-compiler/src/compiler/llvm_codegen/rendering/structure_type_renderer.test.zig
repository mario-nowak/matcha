const std = @import("std");
const expect = @import("testing").expect;
const setupStructureTypeRendererFixture = @import("testing").setupStructureTypeRendererFixture;

pub const StructureTypeRenderer = struct {
    pub const renderStructureTypeDefinitions = struct {
        test "renders each field with its llvm type in definition order" {
            const source =
                \\item Node = structure { value: int; label: string; next: Node; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupStructureTypeRendererFixture(&arena, source);

            const rendered = fixture.structure_type_renderer.renderStructureTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch("%matcha_structure_0_Node = type { i64, %String, ptr }");
        }

        test "omits fields without a runtime representation" {
            const source =
                \\item Record = structure { erased: unit; value: int; label: string; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupStructureTypeRendererFixture(&arena, source);

            const rendered = fixture.structure_type_renderer.renderStructureTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch("%matcha_structure_0_Record = type { i64, %String }");
        }

        test "renders nothing for a structure without runtime fields" {
            const source =
                \\item Empty = structure { value: unit; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupStructureTypeRendererFixture(&arena, source);

            const rendered = fixture.structure_type_renderer.renderStructureTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch("");
        }

        test "separates structure definitions with a newline" {
            const source =
                \\item First = structure { value: int; };
                \\item Empty = structure { value: unit; };
                \\item Second = structure { value: int; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupStructureTypeRendererFixture(&arena, source);

            const rendered = fixture.structure_type_renderer.renderStructureTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_structure_0_First = type { i64 }
                \\%matcha_structure_2_Second = type { i64 }
            );
        }
    };
};
