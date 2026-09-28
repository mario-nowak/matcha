const std = @import("std");
const expect = @import("testing").expect;
const setupStructureTypeRendererFixture = @import("testing").setupUnionTypeRendererFixture;

pub const UnionTypeRenderer = struct {
    pub const renderUnionTypeDefinitions = struct {
        test "xxx" {
            const source =
                \\item IntResult = union {
                \\    None,
                \\    Some: int,
                \\};
                \\item StringResult = union {
                \\    None,
                \\    Some: string,
                \\};
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupStructureTypeRendererFixture(&arena, source);

            const result = fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(result).toMatch(
                \\matcha_union_0__IntResult__case_0__None
                \\matcha_union_0__IntResult__case_1__Some
                \\matcha_union_1__StringResult__case_0__None
                \\matcha_union_1__StringResult__case_1__Some
            );
        }
    };
};
