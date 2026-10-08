const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

pub const RuntimeSymbolRenderer = struct {
    pub const renderDeclarations = struct {
        test "always declares the garbage collector allocation and argument functions" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = try runtime_symbol_renderer.renderDeclarations(.{});

            try expect(rendered).toMatch(
                \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
            );
        }

        test "declares a runtime function only when it is required" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = try runtime_symbol_renderer.renderDeclarations(.{ .print_int = true });

            try expect(rendered).toMatch(
                \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                \\declare void @matcha.compiler_module.builtin.function.printInt(i64)
            );
        }

        test "declares every runtime function when all are required" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const runtime_symbol_renderer = llvm_codegen.RuntimeSymbolRenderer.init(arena.allocator());

            const rendered = try runtime_symbol_renderer.renderDeclarations(.{
                .print_int = true,
                .print_string = true,
                .read_file = true,
                .read_line = true,
                .get_arguments = true,
                .start_process = true,
                .string_concatenate = true,
                .string_compare = true,
                .string_trim = true,
                .string_split = true,
                .string_to_int = true,
                .string_slice = true,
                .int_to_string = true,
                .panic_index_out_of_bounds = true,
                .panic_division_by_zero = true,
                .panic_division_overflow = true,
                .array_append_slot = true,
            });

            try expect(rendered).toMatch(
                \\declare void @matcha.compiler_module.runtime.function.initiateGarbageCollector()
                \\declare ptr @matcha.compiler_module.runtime.function.allocate(i64)
                \\declare ptr @matcha.compiler_module.runtime.function.allocateAtomic(i64)
                \\declare void @matcha.compiler_module.runtime.function.initArguments(i32, ptr)
                \\declare void @matcha.compiler_module.builtin.function.printInt(i64)
                \\declare void @matcha.compiler_module.builtin.function.printString(ptr, i64)
                \\declare void @matcha.compiler_module.builtin.function.readFile(ptr, ptr, i64)
                \\declare void @matcha.compiler_module.builtin.function.readLine(ptr)
                \\declare ptr @matcha.compiler_module.builtin.function.getArguments()
                \\declare void @matcha.compiler_module.builtin.function.startProcess(ptr, ptr, i64, ptr)
                \\declare void @matcha.compiler_module.runtime.function.stringConcatenate(ptr, ptr, i64, ptr, i64)
                \\declare i1 @matcha.compiler_module.runtime.function.stringCompare(ptr, i64, ptr, i64)
                \\declare void @matcha.compiler_module.builtin.type.string.method.trim(ptr, ptr, i64)
                \\declare ptr @matcha.compiler_module.builtin.type.string.method.split(ptr, i64, ptr, i64)
                \\declare i64 @matcha.compiler_module.builtin.type.string.method.toInt(ptr, i64)
                \\declare void @matcha.compiler_module.builtin.type.string.method.slice(ptr, ptr, i64, i64, i64)
                \\declare void @matcha.compiler_module.builtin.type.int.method.toString(ptr, i64)
                \\declare void @matcha.compiler_module.runtime.function.panicIndexOutOfBounds(i64, i64, i64, i64) noreturn
                \\declare void @matcha.compiler_module.runtime.function.panicDivisionByZero(i64, i64) noreturn
                \\declare void @matcha.compiler_module.runtime.function.panicDivisionOverflow(i64, i64) noreturn
                \\declare ptr @matcha.compiler_module.runtime.function.arrayAppendSlot(ptr, i64)
            );
        }
    };
};
