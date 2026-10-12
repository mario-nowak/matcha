const std = @import("std");
const expect = @import("testing").expect;
const setupModuleLoaderFixture = @import("testing").setupModuleLoaderFixture;

pub const ModuleLoader = struct {
    pub const load = struct {
        test "loads the modules that the root module imports" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { Point } = import \"geometry.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "geometry.mt", .data = "export item Point = structure { x: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            try expect(program.modules).toMatch(.{
                .{ .statements = .{.{ .kind = .{ .item_definition = .{ .definition = .{ .import = .{} } } } }} },
                .{ .statements = .{.{ .kind = .{ .item_definition = .{ .definition = .{ .structure = .{} } } } }} },
            });
            try expect(fixture.source_registry.get(1).path).toMatch(try fixture.pathOf("geometry.mt"));
        }

        test "records the module that each import item refers to" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { Point } = import \"geometry.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "geometry.mt", .data = "export item Point = structure { x: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            const import_node_id = program.modules[0].statements[0].id;
            try expect(program.import_target_by_node_id.get(import_node_id).?).toMatch(.{ .module = 1 });
        }

        test "resolves an import path relative to the importing module" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.makePath("lib");
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { format } = import \"lib/text.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "lib/text.mt", .data = "item { Buffer } = import \"buffer.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "lib/buffer.mt", .data = "export item Buffer = structure { length: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            _ = try fixture.load("main.mt");

            try expect(fixture.source_registry.get(2).path).toMatch(try fixture.pathOf("lib/buffer.mt"));
        }

        test "loads a module once when several modules import it" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { A } = import \"a.mt\"; item { B } = import \"b.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "a.mt", .data = "item { Shared } = import \"shared.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "b.mt", .data = "item { Shared } = import \"shared.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "shared.mt", .data = "export item Shared = structure { x: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            try std.testing.expectEqual(4, program.modules.len);
        }

        test "loads a module once when different paths lead to it" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.makePath("lib");
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { A } = import \"a.mt\"; item { B } = import \"./lib/../a.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "a.mt", .data = "export item A = structure { x: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            try std.testing.expectEqual(2, program.modules.len);
        }

        test "loads modules that import each other once" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { A } = import \"a.mt\";" });
            try directory.dir.writeFile(.{ .sub_path = "a.mt", .data = "item { Main } = import \"main.mt\";" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            try std.testing.expectEqual(2, program.modules.len);
            try expect(program.import_target_by_node_id.get(program.modules[1].statements[0].id).?).toMatch(.{ .module = 0 });
        }

        test "reports a missing module at its import path" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { A } = import \"missing.mt\";" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const result = fixture.load("main.mt");

            try expect(result).toBeError(error.DiagnosticsEmitted);
            try expect(fixture.diagnostic_store.items()).toMatch(.{
                .{ .message = "cannot find module 'missing.mt'", .span = .{ .module_id = 0, .column = 21 } },
            });
        }

        test "records the builtins as the target of a builtin import" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { printInt } = import \"builtin\";" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const program = try fixture.load("main.mt");

            try std.testing.expectEqual(1, program.modules.len);
            try expect(program.import_target_by_node_id.get(program.modules[0].statements[0].id).?).toMatch(.builtins);
        }

        test "reports an import path without the .mt extension" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var directory = std.testing.tmpDir(.{});
            defer directory.cleanup();
            try directory.dir.writeFile(.{ .sub_path = "main.mt", .data = "item { Point } = import \"geometry\";" });
            try directory.dir.writeFile(.{ .sub_path = "geometry", .data = "export item Point = structure { x: int; };" });
            const fixture = try setupModuleLoaderFixture(&arena, &directory);

            const result = fixture.load("main.mt");

            try expect(result).toBeError(error.DiagnosticsEmitted);
            try expect(fixture.diagnostic_store.items()).toMatch(.{
                .{ .message = "import path 'geometry' must end with '.mt'" },
            });
        }
    };
};
