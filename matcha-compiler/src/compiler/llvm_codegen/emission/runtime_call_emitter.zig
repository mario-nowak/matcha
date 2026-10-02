const std = @import("std");
const lowering = @import("lowering");
const runtime_symbols = @import("runtime_symbols");

const FunctionIrBuilder = @import("function_ir_builder.zig").FunctionIrBuilder;
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const Register = function_symbol_generator_module.Register;

pub const RuntimeStringParts = struct {
    pointer_register: Register,
    length_register: Register,
};

/// Emits calls into the Matcha runtime. It records every runtime function it emits a call to, so the module
/// declares exactly the functions it calls.
pub const RuntimeCallEmitter = struct {
    allocator: std.mem.Allocator,
    runtime_requirements: runtime_symbols.RuntimeRequirements,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .runtime_requirements = .{},
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn reset(self: *@This()) void {
        self.runtime_requirements.reset();
    }

    pub fn emitInitiateGarbageCollectorCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
    ) void {
        const init_instruction = std.fmt.allocPrint(
            self.allocator,
            "call void @{s}()",
            .{runtime_symbols.runtime_initiate_garbage_collector_function_name},
        ) catch unreachable;
        builder.emitInstruction(init_instruction);
    }

    pub fn emitInitializeArgumentsCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
    ) void {
        const init_instruction = std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(i32 %argc, ptr %argv)",
            .{runtime_symbols.runtime_init_arguments_function_name},
        ) catch unreachable;
        builder.emitInstruction(init_instruction);
    }

    pub fn emitPrintIntCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        integer_register: Register,
    ) void {
        self.runtime_requirements.print_int = true;
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(i64 {s})",
            .{ runtime_symbols.runtime_print_int_function_name, integer_register },
        ) catch unreachable);
    }

    pub fn emitPrintStringCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        string_parts: RuntimeStringParts,
    ) void {
        self.runtime_requirements.print_string = true;
        const print_instruction = std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s}, i64 {s})",
            .{
                runtime_symbols.runtime_print_string_function_name,
                string_parts.pointer_register,
                string_parts.length_register,
            },
        ) catch unreachable;
        builder.emitInstruction(print_instruction);
    }

    pub fn emitReadFileCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        path_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.read_file = true;
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_read_file_function_name,
            path_parts,
        );
    }

    pub fn emitReadLineCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) Register {
        self.runtime_requirements.read_line = true;
        return self.emitZeroInputStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_read_line_function_name,
        );
    }

    pub fn emitGetArgumentsCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) Register {
        self.runtime_requirements.get_arguments = true;
        const result_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}()",
            .{ result_register, runtime_symbols.runtime_get_arguments_function_name },
        ) catch unreachable);
        return result_register;
    }

    pub fn emitStringConcatenateCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.string_concatenate = true;
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, lowering.llvm_type.string_llvm_type);
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                runtime_symbols.runtime_string_concatenate_function_name,
                result_storage,
                left_parts.pointer_register,
                left_parts.length_register,
                right_parts.pointer_register,
                right_parts.length_register,
            },
        ) catch unreachable);

        const result_register = symbol_generator.generateRegister();
        builder.emitLoad(result_register, result_storage, lowering.llvm_type.string_llvm_type);
        return result_register;
    }

    pub fn emitStringCompareCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.string_compare = true;
        const result_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call i1 @{s}(ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                result_register,
                runtime_symbols.runtime_string_compare_function_name,
                left_parts.pointer_register,
                left_parts.length_register,
                right_parts.pointer_register,
                right_parts.length_register,
            },
        ) catch unreachable);
        return result_register;
    }

    pub fn emitStringTrimCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.string_trim = true;
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_string_trim_function_name,
            string_parts,
        );
    }

    pub fn emitStringSplitCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        source_parts: RuntimeStringParts,
        delimiter_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.string_split = true;
        const result_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}(ptr {s}, i64 {s}, ptr {s}, i64 {s})",
            .{
                result_register,
                runtime_symbols.runtime_string_split_function_name,
                source_parts.pointer_register,
                source_parts.length_register,
                delimiter_parts.pointer_register,
                delimiter_parts.length_register,
            },
        ) catch unreachable);
        return result_register;
    }

    pub fn emitStringToIntCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) Register {
        self.runtime_requirements.string_to_int = true;
        const result_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call i64 @{s}(ptr {s}, i64 {s})",
            .{
                result_register,
                runtime_symbols.runtime_string_to_int_function_name,
                string_parts.pointer_register,
                string_parts.length_register,
            },
        ) catch unreachable);
        return result_register;
    }

    pub fn emitIntToStringCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        integer_register: Register,
    ) Register {
        self.runtime_requirements.int_to_string = true;
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, lowering.llvm_type.string_llvm_type);
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s}, i64 {s})",
            .{
                runtime_symbols.runtime_int_to_string_function_name,
                result_storage,
                integer_register,
            },
        ) catch unreachable);

        const result_register = symbol_generator.generateRegister();
        builder.emitLoad(result_register, result_storage, lowering.llvm_type.string_llvm_type);
        return result_register;
    }

    pub fn emitPanicIndexOutOfBoundsCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        line: usize,
        column: usize,
        index_register: Register,
        length_register: Register,
    ) void {
        self.runtime_requirements.panic_index_out_of_bounds = true;
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(i64 {d}, i64 {d}, i64 {s}, i64 {s})",
            .{
                runtime_symbols.runtime_panic_index_out_of_bounds_function_name,
                line,
                column,
                index_register,
                length_register,
            },
        ) catch unreachable);
    }

    pub fn emitArrayAppendSlotCall(
        self: *@This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        array_register: Register,
        element_llvm_type: []const u8,
    ) Register {
        self.runtime_requirements.array_append_slot = true;
        const slot_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}(ptr {s}, i64 {s})",
            .{
                slot_register,
                runtime_symbols.runtime_array_append_slot_function_name,
                array_register,
                self.sizeOf(element_llvm_type, 1),
            },
        ) catch unreachable);

        return slot_register;
    }

    /// Allocates garbage-collected memory for `count` values of `llvm_type`, which the collector scans for pointers.
    pub fn emitAllocateCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        llvm_type: []const u8,
        count: usize,
    ) Register {
        const memory_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}(i64 {s})",
            .{ memory_register, runtime_symbols.runtime_allocate_function_name, self.sizeOf(llvm_type, count) },
        ) catch unreachable);

        return memory_register;
    }

    /// Allocates garbage-collected memory of `byte_count` bytes, which the collector does not scan for pointers.
    pub fn emitAllocateAtomicCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        byte_count: usize,
    ) Register {
        const memory_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}(i64 {d})",
            .{ memory_register, runtime_symbols.runtime_allocate_atomic_function_name, byte_count },
        ) catch unreachable);

        return memory_register;
    }

    /// Renders the size in bytes of `count` values of `llvm_type` as a constant expression. LLVM has no `sizeof`, so
    /// this computes the address of the element after the last one, starting from a null pointer.
    fn sizeOf(self: *const @This(), llvm_type: []const u8, count: usize) []const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64)",
            .{ llvm_type, count },
        ) catch unreachable;
    }

    fn emitStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
        string_parts: RuntimeStringParts,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, lowering.llvm_type.string_llvm_type);
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s}, ptr {s}, i64 {s})",
            .{
                runtime_function_name,
                result_storage,
                string_parts.pointer_register,
                string_parts.length_register,
            },
        ) catch unreachable);

        const result_register = symbol_generator.generateRegister();
        builder.emitLoad(result_register, result_storage, lowering.llvm_type.string_llvm_type);

        return result_register;
    }

    fn emitZeroInputStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, lowering.llvm_type.string_llvm_type);
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s})",
            .{ runtime_function_name, result_storage },
        ) catch unreachable);

        const result_register = symbol_generator.generateRegister();
        builder.emitLoad(result_register, result_storage, lowering.llvm_type.string_llvm_type);
        return result_register;
    }
};
