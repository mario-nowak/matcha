const std = @import("std");
const expect = @import("testing").expect;
const setupUnionTypeRendererFixture = @import("testing").setupUnionTypeRendererFixture;

pub const UnionTypeRenderer = struct {
    pub const renderUnionTypeDefinitions = struct {
        test "renders a unit case as a type with only the case index" {
            const source =
                \\item Signal = union { Ready };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__Signal__case_0__Ready = type { i32 }
            );
        }

        test "renders a payload case as a type with the case index and the payload" {
            const source =
                \\item Count = union { Value: int };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__Count__case_0__Value = type { i32, i64 }
            );
        }

        test "renders each payload with its llvm type" {
            const source =
                \\item User = structure { name: string; };
                \\item Payload = union { Number: int, Text: string, Owner: User, Owners: User[] };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_1__Payload__case_0__Number = type { i32, i64 }
                \\%matcha_union_1__Payload__case_1__Text = type { i32, %String }
                \\%matcha_union_1__Payload__case_2__Owner = type { i32, ptr }
                \\%matcha_union_1__Payload__case_3__Owners = type { i32, ptr }
            );
        }

        test "renders a unit payload as a type with only the case index" {
            const source =
                \\item Signal = union { Ready: unit };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__Signal__case_0__Ready = type { i32 }
            );
        }

        test "renders a payload that refers to its own union as a pointer" {
            const source =
                \\item Tree = union { Leaf: int, Parent: Tree };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__Tree__case_0__Leaf = type { i32, i64 }
                \\%matcha_union_0__Tree__case_1__Parent = type { i32, ptr }
            );
        }

        test "numbers the cases in declaration order" {
            const source =
                \\item Direction = union { North, East, South };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__Direction__case_0__North = type { i32 }
                \\%matcha_union_0__Direction__case_1__East = type { i32 }
                \\%matcha_union_0__Direction__case_2__South = type { i32 }
            );
        }

        test "renders every case of one union before the cases of the next union" {
            const source =
                \\item First = union { A: int, B };
                \\item Second = union { C: int, D };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__First__case_0__A = type { i32, i64 }
                \\%matcha_union_0__First__case_1__B = type { i32 }
                \\%matcha_union_1__Second__case_0__C = type { i32, i64 }
                \\%matcha_union_1__Second__case_1__D = type { i32 }
            );
        }

        test "separates union type definitions with a newline" {
            const source =
                \\item First = union { A };
                \\item Second = union { B };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha_union_0__First__case_0__A = type { i32 }
                \\%matcha_union_1__Second__case_0__B = type { i32 }
            );
        }

        test "renders nothing when the program has no unions" {
            const source =
                \\item User = structure { name: string; };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch("");
        }
    };
};
