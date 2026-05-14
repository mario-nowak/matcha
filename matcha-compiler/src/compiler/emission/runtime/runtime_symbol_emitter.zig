const std = @import("std");

const runtime_symbols = @import("runtime_symbols.zig");
const RuntimeRequirements = runtime_symbols.RuntimeRequirements;

pub const RuntimeSymbolEmitter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn emitDeclarations(
        self: *const @This(),
        requirements: RuntimeRequirements,
    ) []const u8 {
        var runtime_symbol_declarations = std.ArrayList(u8){};
        defer runtime_symbol_declarations.deinit(self.allocator);

        runtime_symbol_declarations.writer(self.allocator).print(
            \\declare void @matcha_initiate_garbage_collector()
            \\declare ptr @matcha_allocate(i64)
            \\declare ptr @matcha_allocate_atomic(i64)
            \\declare void @matcha_init_arguments(i32, ptr)
        ,
            .{},
        ) catch unreachable;

        if (requirements.print_int) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(i64)",
                .{runtime_symbols.runtime_print_int_function_name},
            ) catch unreachable;
        }
        if (requirements.print_string) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, i64)",
                .{runtime_symbols.runtime_print_string_function_name},
            ) catch unreachable;
        }
        if (requirements.read_file) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, ptr, i64)",
                .{runtime_symbols.runtime_read_file_function_name},
            ) catch unreachable;
        }
        if (requirements.read_line) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr)",
                .{runtime_symbols.runtime_read_line_function_name},
            ) catch unreachable;
        }
        if (requirements.get_arguments) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare ptr @{s}()",
                .{runtime_symbols.runtime_get_arguments_function_name},
            ) catch unreachable;
        }
        if (requirements.string_concatenate) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, ptr, i64, ptr, i64)",
                .{runtime_symbols.runtime_string_concatenate_function_name},
            ) catch unreachable;
        }
        if (requirements.string_compare) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare i1 @{s}(ptr, i64, ptr, i64)",
                .{runtime_symbols.runtime_string_compare_function_name},
            ) catch unreachable;
        }
        if (requirements.string_trim) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, ptr, i64)",
                .{runtime_symbols.runtime_string_trim_function_name},
            ) catch unreachable;
        }
        if (requirements.string_split) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare ptr @{s}(ptr, i64, ptr, i64)",
                .{runtime_symbols.runtime_string_split_function_name},
            ) catch unreachable;
        }
        if (requirements.string_to_int) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare i64 @{s}(ptr, i64)",
                .{runtime_symbols.runtime_string_to_int_function_name},
            ) catch unreachable;
        }
        if (requirements.int_to_string) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, i64)",
                .{runtime_symbols.runtime_int_to_string_function_name},
            ) catch unreachable;
        }
        if (requirements.panic_index_out_of_bounds) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(i64, i64, i64, i64) noreturn",
                .{runtime_symbols.runtime_panic_index_out_of_bounds_function_name},
            ) catch unreachable;
        }
        if (requirements.array_append_slot) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare ptr @{s}(ptr, i64)",
                .{runtime_symbols.runtime_array_append_slot_function_name},
            ) catch unreachable;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{runtime_symbol_declarations.items}) catch unreachable;
    }
};
