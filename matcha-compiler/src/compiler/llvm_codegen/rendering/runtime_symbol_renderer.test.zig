const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

pub const RuntimeSymbolRenderer = struct {
    pub const renderDeclarations = struct {
        test "always declares the garbage collector allocation and argument functions" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = runtime_symbol_renderer.renderDeclarations(.{});

            try expect(rendered).toMatch(
                \\declare void @matcha_initiate_garbage_collector()
                \\declare ptr @matcha_allocate(i64)
                \\declare ptr @matcha_allocate_atomic(i64)
                \\declare void @matcha_init_arguments(i32, ptr)
            );
        }

        test "declares a runtime function only when it is required" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = runtime_symbol_renderer.renderDeclarations(.{ .print_int = true });

            try expect(rendered).toMatch(
                \\declare void @matcha_initiate_garbage_collector()
                \\declare ptr @matcha_allocate(i64)
                \\declare ptr @matcha_allocate_atomic(i64)
                \\declare void @matcha_init_arguments(i32, ptr)
                \\declare void @matcha_print_int(i64)
            );
        }

        test "declares every runtime function when all are required" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = runtime_symbol_renderer.renderDeclarations(.{
                .print_int = true,
                .print_string = true,
                .read_file = true,
                .read_line = true,
                .get_arguments = true,
                .string_concatenate = true,
                .string_compare = true,
                .string_trim = true,
                .string_split = true,
                .string_to_int = true,
                .int_to_string = true,
                .panic_index_out_of_bounds = true,
                .array_append_slot = true,
            });

            try expect(rendered).toMatch(
                \\declare void @matcha_initiate_garbage_collector()
                \\declare ptr @matcha_allocate(i64)
                \\declare ptr @matcha_allocate_atomic(i64)
                \\declare void @matcha_init_arguments(i32, ptr)
                \\declare void @matcha_print_int(i64)
                \\declare void @matcha_print_string(ptr, i64)
                \\declare void @matcha_read_file(ptr, ptr, i64)
                \\declare void @matcha_read_line(ptr)
                \\declare ptr @matcha_get_arguments()
                \\declare void @matcha_string_concatenate(ptr, ptr, i64, ptr, i64)
                \\declare i1 @matcha_string_compare(ptr, i64, ptr, i64)
                \\declare void @matcha_string_trim(ptr, ptr, i64)
                \\declare ptr @matcha_string_split(ptr, i64, ptr, i64)
                \\declare i64 @matcha_string_to_int(ptr, i64)
                \\declare void @matcha_int_to_string(ptr, i64)
                \\declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn
                \\declare ptr @matcha_array_append_slot(ptr, i64)
            );
        }
    };
};
