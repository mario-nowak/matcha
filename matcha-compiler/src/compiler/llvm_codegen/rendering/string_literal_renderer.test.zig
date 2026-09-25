const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

const StringLiteralPool = llvm_codegen.StringLiteralPool;

pub const StringLiteralRenderer = struct {
    pub const renderGlobals = struct {
        test "renders a string literal as a private byte array constant" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var string_literal_pool = StringLiteralPool.init(arena.allocator());
            _ = string_literal_pool.registerLiteral(0, "hello");
            var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(arena.allocator());

            const rendered = string_literal_renderer.renderGlobals(&string_literal_pool);

            try expect(rendered).toMatch(
                \\@.string_literal_0 = private unnamed_addr constant [5 x i8] c"hello"
            );
        }

        test "escapes quotes backslashes and control characters as hex bytes" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var string_literal_pool = StringLiteralPool.init(arena.allocator());
            _ = string_literal_pool.registerLiteral(0, "a\"b\\c\n");
            var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(arena.allocator());

            const rendered = string_literal_renderer.renderGlobals(&string_literal_pool);

            try expect(rendered).toMatch(
                \\@.string_literal_0 = private unnamed_addr constant [6 x i8] c"a\22b\5Cc\0A"
            );
        }

        test "uses the byte length for non-ascii content" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var string_literal_pool = StringLiteralPool.init(arena.allocator());
            _ = string_literal_pool.registerLiteral(0, "é");
            var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(arena.allocator());

            const rendered = string_literal_renderer.renderGlobals(&string_literal_pool);

            try expect(rendered).toMatch(
                \\@.string_literal_0 = private unnamed_addr constant [2 x i8] c"\C3\A9"
            );
        }

        test "separates globals with a newline" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var string_literal_pool = StringLiteralPool.init(arena.allocator());
            _ = string_literal_pool.registerLiteral(0, "first");
            _ = string_literal_pool.registerLiteral(1, "second");
            var string_literal_renderer = llvm_codegen.StringLiteralRenderer.init(arena.allocator());

            const rendered = string_literal_renderer.renderGlobals(&string_literal_pool);

            try expect(rendered).toMatch(
                \\@.string_literal_0 = private unnamed_addr constant [5 x i8] c"first"
                \\@.string_literal_1 = private unnamed_addr constant [6 x i8] c"second"
            );
        }
    };
};
