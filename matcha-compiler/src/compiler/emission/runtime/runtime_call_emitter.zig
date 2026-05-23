const std = @import("std");
const function_emission = @import("function_emission");

const runtime_symbols = @import("runtime_symbols.zig");

const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;
const Register = function_emission.Register;

pub const RuntimeStringParts = struct {
    pointer_register: Register,
    length_register: Register,
};

pub const RuntimeCallEmitter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        integer_register: Register,
    ) void {
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(i64 {s})",
            .{ runtime_symbols.runtime_print_int_function_name, integer_register },
        ) catch unreachable);
    }

    pub fn emitPrintStringCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        string_parts: RuntimeStringParts,
    ) void {
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        path_parts: RuntimeStringParts,
    ) Register {
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_read_file_function_name,
            path_parts,
        );
    }

    pub fn emitReadLineCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) Register {
        return self.emitZeroInputStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_read_line_function_name,
        );
    }

    pub fn emitGetArgumentsCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
    ) Register {
        const result_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}()",
            .{ result_register, runtime_symbols.runtime_get_arguments_function_name },
        ) catch unreachable);
        return result_register;
    }

    pub fn emitStringConcatenateCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, "%String");
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
        builder.emitLoad(result_register, result_storage, "%String");
        return result_register;
    }

    pub fn emitStringCompareCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        left_parts: RuntimeStringParts,
        right_parts: RuntimeStringParts,
    ) Register {
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) Register {
        return self.emitStringOutputCall(
            builder,
            symbol_generator,
            runtime_symbols.runtime_string_trim_function_name,
            string_parts,
        );
    }

    pub fn emitStringSplitCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        source_parts: RuntimeStringParts,
        delimiter_parts: RuntimeStringParts,
    ) Register {
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        string_parts: RuntimeStringParts,
    ) Register {
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        integer_register: Register,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, "%String");
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
        builder.emitLoad(result_register, result_storage, "%String");
        return result_register;
    }

    pub fn emitPanicIndexOutOfBoundsCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        line: usize,
        column: usize,
        index_register: Register,
        length_register: Register,
    ) void {
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
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        array_register: Register,
        element_llvm_type: []const u8,
    ) Register {
        const slot_register = symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @{s}(ptr {s}, i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 1) to i64))",
            .{
                slot_register,
                runtime_symbols.runtime_array_append_slot_function_name,
                array_register,
                element_llvm_type,
            },
        ) catch unreachable);
        return slot_register;
    }

    fn emitStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
        string_parts: RuntimeStringParts,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, "%String");
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
        builder.emitLoad(result_register, result_storage, "%String");
        return result_register;
    }

    fn emitZeroInputStringOutputCall(
        self: *const @This(),
        builder: *FunctionIrBuilder,
        symbol_generator: *FunctionSymbolGenerator,
        runtime_function_name: []const u8,
    ) Register {
        const result_storage = symbol_generator.generateStorage();
        builder.emitAlloca(result_storage, "%String");
        builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s})",
            .{ runtime_function_name, result_storage },
        ) catch unreachable);

        const result_register = symbol_generator.generateRegister();
        builder.emitLoad(result_register, result_storage, "%String");
        return result_register;
    }
};
