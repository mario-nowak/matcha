// The runtime exports its functions under these names, so the compiler and the runtime share one spelling.
// The helpers build every name from `<kind>.<name>` pairs, as the IR naming plan describes.
const builtin_module = "matcha.compiler_module.builtin";
const runtime_module = "matcha.compiler_module.runtime";

fn builtinFunction(comptime name: []const u8) []const u8 {
    return builtin_module ++ ".function." ++ name;
}

fn builtinMethod(comptime type_name: []const u8, comptime name: []const u8) []const u8 {
    return builtinType(type_name) ++ ".method." ++ name;
}

pub fn builtinType(comptime name: []const u8) []const u8 {
    return builtin_module ++ ".type." ++ name;
}

fn runtimeFunction(comptime name: []const u8) []const u8 {
    return runtime_module ++ ".function." ++ name;
}

pub const runtime_allocate_function_name = runtimeFunction("allocate");
pub const runtime_allocate_atomic_function_name = runtimeFunction("allocateAtomic");
pub const builtin_print_int_function_name = builtinFunction("printInt");
pub const builtin_print_string_function_name = builtinFunction("printString");
pub const builtin_read_file_function_name = builtinFunction("readFile");
pub const builtin_read_line_function_name = builtinFunction("readLine");
pub const runtime_initiate_garbage_collector_function_name = runtimeFunction("initiateGarbageCollector");
pub const runtime_init_arguments_function_name = runtimeFunction("initArguments");
pub const builtin_get_arguments_function_name = builtinFunction("getArguments");
pub const runtime_string_concatenate_function_name = runtimeFunction("stringConcatenate");
pub const runtime_string_compare_function_name = runtimeFunction("stringCompare");
pub const builtin_string_trim_method_name = builtinMethod("string", "trim");
pub const builtin_string_split_method_name = builtinMethod("string", "split");
pub const builtin_string_to_int_method_name = builtinMethod("string", "toInt");
pub const builtin_int_to_string_method_name = builtinMethod("int", "toString");
pub const runtime_panic_index_out_of_bounds_function_name = runtimeFunction("panicIndexOutOfBounds");
pub const runtime_panic_division_by_zero_function_name = runtimeFunction("panicDivisionByZero");
pub const runtime_panic_division_overflow_function_name = runtimeFunction("panicDivisionOverflow");
pub const runtime_array_append_slot_function_name = runtimeFunction("arrayAppendSlot");

pub const RuntimeRequirements = struct {
    print_int: bool = false,
    print_string: bool = false,
    read_file: bool = false,
    read_line: bool = false,
    get_arguments: bool = false,
    string_concatenate: bool = false,
    string_compare: bool = false,
    string_trim: bool = false,
    string_split: bool = false,
    string_to_int: bool = false,
    int_to_string: bool = false,
    panic_index_out_of_bounds: bool = false,
    panic_division_by_zero: bool = false,
    panic_division_overflow: bool = false,
    array_append_slot: bool = false,

    pub fn reset(self: *@This()) void {
        self.* = .{};
    }
};
