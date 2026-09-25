const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

const RuntimeRequirements = llvm_codegen.RuntimeRequirements;
const RuntimeStringParts = llvm_codegen.RuntimeStringParts;

pub const RuntimeCallEmitter = struct {
    pub const emitPrintIntCall = struct {
        test "records the print int runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());

            runtime_call_emitter.emitPrintIntCall(&function_ir_builder, "%value");

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .print_int = true });
        }
    };

    pub const emitPrintStringCall = struct {
        test "records the print string runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            runtime_call_emitter.emitPrintStringCall(&function_ir_builder, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .print_string = true });
        }
    };

    pub const emitReadFileCall = struct {
        test "records the read file runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitReadFileCall(&function_ir_builder, &function_symbol_generator, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .read_file = true });
        }
    };

    pub const emitReadLineCall = struct {
        test "records the read line runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            _ = runtime_call_emitter.emitReadLineCall(&function_ir_builder, &function_symbol_generator);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .read_line = true });
        }
    };

    pub const emitGetArgumentsCall = struct {
        test "records the get arguments runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            _ = runtime_call_emitter.emitGetArgumentsCall(&function_ir_builder, &function_symbol_generator);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .get_arguments = true });
        }
    };

    pub const emitStringConcatenateCall = struct {
        test "records the string concatenate runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitStringConcatenateCall(&function_ir_builder, &function_symbol_generator, string_parts, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .string_concatenate = true });
        }
    };

    pub const emitStringCompareCall = struct {
        test "records the string compare runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitStringCompareCall(&function_ir_builder, &function_symbol_generator, string_parts, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .string_compare = true });
        }
    };

    pub const emitStringTrimCall = struct {
        test "records the string trim runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitStringTrimCall(&function_ir_builder, &function_symbol_generator, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .string_trim = true });
        }
    };

    pub const emitStringSplitCall = struct {
        test "records the string split runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitStringSplitCall(&function_ir_builder, &function_symbol_generator, string_parts, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .string_split = true });
        }
    };

    pub const emitStringToIntCall = struct {
        test "records the string to int runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const string_parts = RuntimeStringParts{ .pointer_register = "%pointer", .length_register = "%length" };

            _ = runtime_call_emitter.emitStringToIntCall(&function_ir_builder, &function_symbol_generator, string_parts);

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .string_to_int = true });
        }
    };

    pub const emitIntToStringCall = struct {
        test "records the int to string runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            _ = runtime_call_emitter.emitIntToStringCall(&function_ir_builder, &function_symbol_generator, "%value");

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .int_to_string = true });
        }
    };

    pub const emitPanicIndexOutOfBoundsCall = struct {
        test "records the panic index out of bounds runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());

            runtime_call_emitter.emitPanicIndexOutOfBoundsCall(&function_ir_builder, 1, 1, "%index", "%length");

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .panic_index_out_of_bounds = true });
        }
    };

    pub const emitArrayAppendSlotCall = struct {
        test "records the array append slot runtime requirement" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            _ = runtime_call_emitter.emitArrayAppendSlotCall(&function_ir_builder, &function_symbol_generator, "%array", "i64");

            try expect(runtime_call_emitter.runtime_requirements).toMatch(.{ .array_append_slot = true });
        }
    };

    pub const reset = struct {
        test "forgets the recorded runtime requirements" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var runtime_call_emitter = llvm_codegen.RuntimeCallEmitter.init(arena.allocator());
            var function_ir_builder = llvm_codegen.FunctionIrBuilder.init(arena.allocator());
            runtime_call_emitter.emitPrintIntCall(&function_ir_builder, "%value");

            runtime_call_emitter.reset();

            try expect(runtime_call_emitter.runtime_requirements).toMatch(RuntimeRequirements{});
        }
    };
};
