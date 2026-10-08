const std = @import("std");
const lowering = @import("lowering");
const runtime_symbols = @import("runtime_symbols");

const FunctionIrBuilder = @import("function_ir_builder.zig").FunctionIrBuilder;
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const Value = function_symbol_generator_module.Value;

pub const RuntimeStringParts = struct {
    pointer_value: Value,
    length_value: Value,
};

/// Emits calls into the Matcha runtime. It records every runtime function it emits a call to, so the module
/// declares exactly the functions it calls.
pub const RuntimeCallEmitter = struct {
    arena: std.mem.Allocator,
    runtime_requirements: runtime_symbols.RuntimeRequirements,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
            .runtime_requirements = .{},
        };
    }

    pub fn reset(self: *@This()) void {
        self.runtime_requirements.reset();
    }

    pub fn emitInitiateGarbageCollectorCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
    ) !void {
        const init_instruction = try std.fmt.allocPrint(
            self.arena,
            "call void @{s}()",
            .{runtime_symbols.runtime_initiate_garbage_collector_function_name},
        );
        try builder.emitInstruction(init_instruction);
    }

    pub fn emitInitializeArgumentsCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
    ) !void {
        const init_instruction = try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(i32 %parameter.argc, ptr %parameter.argv)",
            .{runtime_symbols.runtime_init_arguments_function_name},
        );
        try builder.emitInstruction(init_instruction);
    }

    pub fn emitPrintIntCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        integer_value: Value,
    ) !void {
        self.runtime_requirements.print_int = true;
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(i64 {s})",
            .{ runtime_symbols.builtin_print_int_function_name, integer_value },
        ));
    }

    pub fn emitPrintStringCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        string_parts: RuntimeStringParts,
    ) !void {
        self.runtime_requirements.print_string = true;
        const print_instruction = try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, i64 {s})",
            .{
                runtime_symbols.builtin_print_string_function_name,
                string_parts.pointer_value,
                string_parts.length_value,
            },
        );
        try builder.emitInstruction(print_instruction);
    }

    pub fn emitReadFileCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        path_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.read_file = true;
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.builtin_read_file_function_name,
            path_parts,
        );
    }

    pub fn emitReadLineCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) !Value {
        self.runtime_requirements.read_line = true;
        return self.emitZeroInputStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.builtin_read_line_function_name,
        );
    }

    pub fn emitGetArgumentsCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) !Value {
        self.runtime_requirements.get_arguments = true;
        const result_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call ptr @{s}()",
            .{ result_value, runtime_symbols.builtin_get_arguments_function_name },
        ));
        return result_value;
    }

    pub fn emitStartProcessCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        command_parts: RuntimeStringParts,
        arguments_value: Value,
    ) !Value {
        self.runtime_requirements.start_process = true;
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s}, ptr {s})",
            .{
                runtime_symbols.builtin_start_process_function_name,
                result_address,
                command_parts.pointer_value,
                command_parts.length_value,
                arguments_value,
            },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);
        return result_value;
    }

    pub fn emitStringConcatenateCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.string_concatenate = true;
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                runtime_symbols.runtime_string_concatenate_function_name,
                result_address,
                left_parts.pointer_value,
                left_parts.length_value,
                right_parts.pointer_value,
                right_parts.length_value,
            },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);
        return result_value;
    }

    pub fn emitStringCompareCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.string_compare = true;
        const result_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call i1 @{s}(ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                result_value,
                runtime_symbols.runtime_string_compare_function_name,
                left_parts.pointer_value,
                left_parts.length_value,
                right_parts.pointer_value,
                right_parts.length_value,
            },
        ));
        return result_value;
    }

    pub fn emitStringTrimCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.string_trim = true;
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.builtin_string_trim_method_name,
            string_parts,
        );
    }

    pub fn emitStringSplitCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        source_parts: RuntimeStringParts,
        delimiter_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.string_split = true;
        const result_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call ptr @{s}(ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                result_value,
                runtime_symbols.builtin_string_split_method_name,
                source_parts.pointer_value,
                source_parts.length_value,
                delimiter_parts.pointer_value,
                delimiter_parts.length_value,
            },
        ));
        return result_value;
    }

    pub fn emitStringToIntCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) !Value {
        self.runtime_requirements.string_to_int = true;
        const result_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call i64 @{s}(ptr {s}, i64 {s})",
            .{
                result_value,
                runtime_symbols.builtin_string_to_int_method_name,
                string_parts.pointer_value,
                string_parts.length_value,
            },
        ));
        return result_value;
    }

    pub fn emitStringSliceCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
        start_value: Value,
        end_value: Value,
    ) !Value {
        self.runtime_requirements.string_slice = true;
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s}, i64 {s}, i64 {s})",
            .{
                runtime_symbols.builtin_string_slice_method_name,
                result_address,
                string_parts.pointer_value,
                string_parts.length_value,
                start_value,
                end_value,
            },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);
        return result_value;
    }

    pub fn emitIntToStringCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        integer_value: Value,
    ) !Value {
        self.runtime_requirements.int_to_string = true;
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, i64 {s})",
            .{
                runtime_symbols.builtin_int_to_string_method_name,
                result_address,
                integer_value,
            },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);
        return result_value;
    }

    pub fn emitPanicIndexOutOfBoundsCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        line: usize,
        column: usize,
        index_value: Value,
        length_value: Value,
    ) !void {
        self.runtime_requirements.panic_index_out_of_bounds = true;
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(i64 {d}, i64 {d}, i64 {s}, i64 {s})",
            .{
                runtime_symbols.runtime_panic_index_out_of_bounds_function_name,
                line,
                column,
                index_value,
                length_value,
            },
        ));
    }

    pub fn emitPanicDivisionByZeroCall(self: *@This(), builder: *FunctionIrBuilder, line: usize, column: usize) !void {
        self.runtime_requirements.panic_division_by_zero = true;
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(i64 {d}, i64 {d})",
            .{ runtime_symbols.runtime_panic_division_by_zero_function_name, line, column },
        ));
    }

    pub fn emitPanicDivisionOverflowCall(self: *@This(), builder: *FunctionIrBuilder, line: usize, column: usize) !void {
        self.runtime_requirements.panic_division_overflow = true;
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(i64 {d}, i64 {d})",
            .{ runtime_symbols.runtime_panic_division_overflow_function_name, line, column },
        ));
    }

    pub fn emitArrayAppendSlotCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        array_value: Value,
        element_llvm_type: []const u8,
    ) !Value {
        self.runtime_requirements.array_append_slot = true;
        const slot_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call ptr @{s}(ptr {s}, i64 {s})",
            .{
                slot_value,
                runtime_symbols.runtime_array_append_slot_function_name,
                array_value,
                try self.sizeOf(element_llvm_type, 1),
            },
        ));

        return slot_value;
    }

    /// Allocates garbage-collected memory for `count` values of `llvm_type`, which the collector scans for pointers.
    pub fn emitAllocateCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        llvm_type: []const u8,
        count: usize,
    ) !Value {
        const memory_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call ptr @{s}(i64 {s})",
            .{ memory_value, runtime_symbols.runtime_allocate_function_name, try self.sizeOf(llvm_type, count) },
        ));

        return memory_value;
    }

    /// Allocates garbage-collected memory of `byte_count` bytes, which the collector does not scan for pointers.
    pub fn emitAllocateAtomicCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        byte_count: usize,
    ) !Value {
        const memory_value = try symbol_generator.generateValueName();
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "{s} = call ptr @{s}(i64 {d})",
            .{ memory_value, runtime_symbols.runtime_allocate_atomic_function_name, byte_count },
        ));

        return memory_value;
    }

    /// Renders the size in bytes of `count` values of `llvm_type` as a constant expression. LLVM has no `sizeof`, so
    /// this computes the address of the element after the last one, starting from a null pointer.
    fn sizeOf(self: *const @This(), llvm_type: []const u8, count: usize) ![]const u8 {
        return std.fmt.allocPrint(
            self.arena,
            "ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64)",
            .{ llvm_type, count },
        );
    }

    fn emitStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
        string_parts: RuntimeStringParts,
    ) !Value {
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s})",
            .{
                runtime_function_name,
                result_address,
                string_parts.pointer_value,
                string_parts.length_value,
            },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);

        return result_value;
    }

    fn emitZeroInputStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
    ) !Value {
        const result_address = try symbol_generator.generateSyntheticAddressName();
        try builder.emitStackAllocation(result_address, lowering.llvm_type.string_llvm_type);
        try builder.emitInstruction(try std.fmt.allocPrint(
            self.arena,
            "call void @{s}(ptr {s})",
            .{ runtime_function_name, result_address },
        ));

        const result_value = try symbol_generator.generateValueName();
        try builder.emitLoad(result_value, result_address, lowering.llvm_type.string_llvm_type);
        return result_value;
    }
};
