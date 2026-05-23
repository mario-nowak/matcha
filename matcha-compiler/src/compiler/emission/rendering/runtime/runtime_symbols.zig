pub const runtime_print_int_function_name = "matcha_print_int";
pub const runtime_print_string_function_name = "matcha_print_string";
pub const runtime_read_file_function_name = "matcha_read_file";
pub const runtime_read_line_function_name = "matcha_read_line";
pub const runtime_init_arguments_function_name = "matcha_init_arguments";
pub const runtime_get_arguments_function_name = "matcha_get_arguments";
pub const runtime_string_concatenate_function_name = "matcha_string_concatenate";
pub const runtime_string_compare_function_name = "matcha_string_compare";
pub const runtime_string_trim_function_name = "matcha_string_trim";
pub const runtime_string_split_function_name = "matcha_string_split";
pub const runtime_string_to_int_function_name = "matcha_string_to_int";
pub const runtime_int_to_string_function_name = "matcha_int_to_string";
pub const runtime_panic_index_out_of_bounds_function_name = "matcha_panic_index_out_of_bounds";
pub const runtime_array_append_slot_function_name = "matcha_array_append_slot";

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
    array_append_slot: bool = false,

    pub fn reset(self: *@This()) void {
        self.* = .{};
    }
};
