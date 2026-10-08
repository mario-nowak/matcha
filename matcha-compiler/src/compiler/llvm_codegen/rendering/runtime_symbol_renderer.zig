const std = @import("std");

const runtime_symbols = @import("runtime_symbols");
const RuntimeRequirements = runtime_symbols.RuntimeRequirements;

pub const RuntimeSymbolRenderer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{ .arena = arena };
    }

    pub fn renderDeclarations(
        self: *const @This(),
        requirements: RuntimeRequirements,
    ) ![]const u8 {
        var runtime_symbol_declarations = std.ArrayList(u8){};

        try runtime_symbol_declarations.print(
            self.arena,
            "declare void @{s}()\ndeclare ptr @{s}(i64)\ndeclare ptr @{s}(i64)\ndeclare void @{s}(i32, ptr)",
            .{
                runtime_symbols.runtime_initiate_garbage_collector_function_name,
                runtime_symbols.runtime_allocate_function_name,
                runtime_symbols.runtime_allocate_atomic_function_name,
                runtime_symbols.runtime_init_arguments_function_name,
            },
        );

        if (requirements.print_int) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(i64)",
                .{runtime_symbols.builtin_print_int_function_name},
            );
        }
        if (requirements.print_string) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, i64)",
                .{runtime_symbols.builtin_print_string_function_name},
            );
        }
        if (requirements.read_file) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, ptr, i64)",
                .{runtime_symbols.builtin_read_file_function_name},
            );
        }
        if (requirements.read_line) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr)",
                .{runtime_symbols.builtin_read_line_function_name},
            );
        }
        if (requirements.get_arguments) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare ptr @{s}()",
                .{runtime_symbols.builtin_get_arguments_function_name},
            );
        }
        if (requirements.start_process) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, ptr, i64, ptr)",
                .{runtime_symbols.builtin_start_process_function_name},
            );
        }
        if (requirements.string_concatenate) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, ptr, i64, ptr, i64)",
                .{runtime_symbols.runtime_string_concatenate_function_name},
            );
        }
        if (requirements.string_compare) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare i1 @{s}(ptr, i64, ptr, i64)",
                .{runtime_symbols.runtime_string_compare_function_name},
            );
        }
        if (requirements.string_trim) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, ptr, i64)",
                .{runtime_symbols.builtin_string_trim_method_name},
            );
        }
        if (requirements.string_split) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare ptr @{s}(ptr, i64, ptr, i64)",
                .{runtime_symbols.builtin_string_split_method_name},
            );
        }
        if (requirements.string_to_int) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare i64 @{s}(ptr, i64)",
                .{runtime_symbols.builtin_string_to_int_method_name},
            );
        }
        if (requirements.int_to_string) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(ptr, i64)",
                .{runtime_symbols.builtin_int_to_string_method_name},
            );
        }
        if (requirements.panic_index_out_of_bounds) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(i64, i64, i64, i64) noreturn",
                .{runtime_symbols.runtime_panic_index_out_of_bounds_function_name},
            );
        }
        if (requirements.panic_division_by_zero) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(i64, i64) noreturn",
                .{runtime_symbols.runtime_panic_division_by_zero_function_name},
            );
        }
        if (requirements.panic_division_overflow) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare void @{s}(i64, i64) noreturn",
                .{runtime_symbols.runtime_panic_division_overflow_function_name},
            );
        }
        if (requirements.array_append_slot) {
            try runtime_symbol_declarations.print(
                self.arena,
                "\ndeclare ptr @{s}(ptr, i64)",
                .{runtime_symbols.runtime_array_append_slot_function_name},
            );
        }

        return runtime_symbol_declarations.toOwnedSlice(self.arena);
    }
};
