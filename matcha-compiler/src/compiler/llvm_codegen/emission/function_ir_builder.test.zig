const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

pub const FunctionIrBuilder = struct {
    pub const render = struct {
        test "hoists storage allocations into the entry block" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitStore("1", "%value", "i64");
            function_ir_builder.emitAlloca("%value", "i64");
            function_ir_builder.emitTerminatorInstruction("ret void");

            const rendered = function_ir_builder.render("example", "void", "");

            try expect(rendered).toMatch(
                \\define void @example() {
                \\entry:
                \\    %value = alloca i64
                \\    store i64 1, ptr %value
                \\    ret void
                \\}
            );
        }

        test "drops instructions after a terminator until the next label" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitTerminatorInstruction("br label %next");
            function_ir_builder.emitInstruction("%dropped = add i64 1, 2");
            function_ir_builder.emitLabel("next");
            function_ir_builder.emitTerminatorInstruction("ret void");

            const rendered = function_ir_builder.render("example", "void", "");

            try expect(rendered).toMatch(
                \\define void @example() {
                \\entry:
                \\    br label %next
                \\next:
                \\    ret void
                \\}
            );
        }

        test "keeps storage allocations emitted after a terminator" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitTerminatorInstruction("ret void");
            function_ir_builder.emitAlloca("%value", "i64");

            const rendered = function_ir_builder.render("example", "void", "");

            try expect(rendered).toMatch(
                \\define void @example() {
                \\entry:
                \\    %value = alloca i64
                \\    ret void
                \\}
            );
        }

        test "renders the return type and parameter list in the signature" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitTerminatorInstruction("ret i64 %value");

            const rendered = function_ir_builder.render("example", "i64", "i64 %value");

            try expect(rendered).toMatch(
                \\define i64 @example(i64 %value) {
                \\entry:
                \\    ret i64 %value
                \\}
            );
        }

        test "starts an empty function in the entry block after reset" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitAlloca("%previous", "i64");
            function_ir_builder.emitLabel("previous_block");
            function_ir_builder.emitTerminatorInstruction("ret void");
            function_ir_builder.reset();
            function_ir_builder.emitTerminatorInstruction("ret void");

            const rendered = function_ir_builder.render("example", "void", "");

            try expect(rendered).toMatch(
                \\define void @example() {
                \\entry:
                \\    ret void
                \\}
            );
        }
    };

    pub const currentLabel = struct {
        test "returns the label of the most recently opened block" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitLabel("next");

            const current_label = function_ir_builder.currentLabel();

            try expect(current_label).toMatch("next");
        }

        test "returns null after a terminator" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            function_ir_builder.emitTerminatorInstruction("ret void");

            const current_label = function_ir_builder.currentLabel();

            try expect(current_label).toMatch(null);
        }
    };
};
