const std = @import("std");
const sources = @import("sources");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

const lowering = llvm_codegen.lowering;

pub const ModuleNameLowerer = struct {
    pub const lower = struct {
        test "names the root module after its file name" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var source_registry = sources.SourceRegistry.init(arena.allocator());
            const root_module_id = try source_registry.add("main.mt", "");
            const module_name_lowerer = lowering.ModuleNameLowerer.init(arena.allocator(), &source_registry);

            const module_name = try module_name_lowerer.lower(root_module_id);

            try expect(module_name).toMatch("matcha.module.main");
        }

        test "adds a directory segment for each directory between the root module and the module" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var source_registry = sources.SourceRegistry.init(arena.allocator());
            _ = try source_registry.add("main.mt", "");
            const module_id = try source_registry.add("lib/text/format.mt", "");
            const module_name_lowerer = lowering.ModuleNameLowerer.init(arena.allocator(), &source_registry);

            const module_name = try module_name_lowerer.lower(module_id);

            try expect(module_name).toMatch("matcha.directory.lib.directory.text.module.format");
        }

        test "ignores the directories above the root module" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var source_registry = sources.SourceRegistry.init(arena.allocator());
            _ = try source_registry.add("projects/app/main.mt", "");
            const module_id = try source_registry.add("projects/app/lib/util.mt", "");
            const module_name_lowerer = lowering.ModuleNameLowerer.init(arena.allocator(), &source_registry);

            const module_name = try module_name_lowerer.lower(module_id);

            try expect(module_name).toMatch("matcha.directory.lib.module.util");
        }

        test "escapes every character except letters, digits, underscores and hyphens" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var source_registry = sources.SourceRegistry.init(arena.allocator());
            _ = try source_registry.add("main.mt", "");
            const module_id = try source_registry.add("my app/user.controller_v-2$.mt", "");
            const module_name_lowerer = lowering.ModuleNameLowerer.init(arena.allocator(), &source_registry);

            const module_name = try module_name_lowerer.lower(module_id);

            try expect(module_name).toMatch("matcha.directory.my$20app.module.user$2Econtroller_v-2$24");
        }
    };
};
