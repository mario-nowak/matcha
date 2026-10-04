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
                \\%matcha.union.Signal.case.Ready = type { i32 }
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
                \\%matcha.union.Count.case.Value = type { i32, i64 }
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
                \\%matcha.union.Payload.case.Number = type { i32, i64 }
                \\%matcha.union.Payload.case.Text = type { i32, %matcha.compiler_module.builtin.type.string }
                \\%matcha.union.Payload.case.Owner = type { i32, ptr }
                \\%matcha.union.Payload.case.Owners = type { i32, ptr }
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
                \\%matcha.union.Signal.case.Ready = type { i32 }
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
                \\%matcha.union.Tree.case.Leaf = type { i32, i64 }
                \\%matcha.union.Tree.case.Parent = type { i32, ptr }
            );
        }

        test "renders the cases in declaration order" {
            const source =
                \\item Direction = union { North, East, South };
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupUnionTypeRendererFixture(&arena, source);

            const rendered = try fixture.union_type_renderer.renderUnionTypeDefinitions(&fixture.lowered_program);

            try expect(rendered).toMatch(
                \\%matcha.union.Direction.case.North = type { i32 }
                \\%matcha.union.Direction.case.East = type { i32 }
                \\%matcha.union.Direction.case.South = type { i32 }
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
                \\%matcha.union.First.case.A = type { i32, i64 }
                \\%matcha.union.First.case.B = type { i32 }
                \\%matcha.union.Second.case.C = type { i32, i64 }
                \\%matcha.union.Second.case.D = type { i32 }
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
                \\%matcha.union.First.case.A = type { i32 }
                \\%matcha.union.Second.case.B = type { i32 }
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
