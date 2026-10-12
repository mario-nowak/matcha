const std = @import("std");
const expect = @import("testing").expect;
const setupStructuralValidatorFixture = @import("testing").setupStructuralValidatorFixture;
const setupStructuralValidatorFixtureFromSourceFiles = @import("testing").setupStructuralValidatorFixtureFromSourceFiles;

test "StructuralValidator > validateProgram: accepts implicit member expressions" {
    const source = "val event = .PageLoad;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    try fixture.validator.validateProgram(&fixture.program);

    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "StructuralValidator > validateProgram: accepts return inside union functions" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = {
        \\        return "event";
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    try fixture.validator.validateProgram(&fixture.program);

    try expect(fixture.diagnostic_store.items()).toMatch(.{});
}

test "StructuralValidator > validateProgram: rejects continue when inside a union function but outside a loop" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = {
        \\        continue;
        \\        "event"
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try setupStructuralValidatorFixture(&arena, source);

    const result = fixture.validator.validateProgram(&fixture.program);

    try expect(result).toBeError(error.DiagnosticsEmitted);
    try expect(fixture.diagnostic_store.items()).toMatch(.{
        .{ .message = "continue is only allowed inside loops" },
    });
}

pub const StructuralValidator = struct {
    pub const validateProgram = struct {
        pub const modules = struct {
            test "rejects a statement other than an item definition in a module other than the root module" {
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupStructuralValidatorFixtureFromSourceFiles(&arena, &.{
                    .{
                        .path = "main.mt",
                        .source =
                        \\item { printInt } = import "builtin";
                        \\printInt(1);"
                        ,
                    },
                    .{
                        .path = "other.mt",
                        .source =
                        \\item { printInt } = import "builtin";
                        \\printInt(2);
                        ,
                    },
                });

                const result = fixture.validator.validateProgram(&fixture.program);

                try expect(result).toBeError(error.DiagnosticsEmitted);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .message = "only item definitions are allowed outside the root module", .span = .{ .module_id = 1 } },
                });
            }

            test "accepts items in a module other than the root module" {
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupStructuralValidatorFixtureFromSourceFiles(&arena, &.{
                    .{
                        .path = "main.mt",
                        .source =
                        \\item { printInt } = import "builtin";
                        \\printInt(1);
                        ,
                    },
                    .{
                        .path = "other.mt",
                        .source = "item Point = structure { x: int; };",
                    },
                });

                try fixture.validator.validateProgram(&fixture.program);

                try expect(fixture.diagnostic_store.items()).toMatch(.{});
            }
        };
    };
};
