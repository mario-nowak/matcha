const std = @import("std");
const runtime = @import("runtime/module.zig");
const symbols = @import("symbols");

pub const SymbolGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn generateStructureFunctionName(
        self: *@This(),
        structure_symbol: symbols.Symbol,
        function_symbol: symbols.Symbol,
    ) []const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "matcha_structure_{d}_{s}__function_{d}_{s}",
            .{
                structure_symbol.id,
                structure_symbol.name,
                function_symbol.id,
                function_symbol.name,
            },
        ) catch unreachable;
    }

    pub fn generateFunctionName(
        self: *@This(),
        function_symbol: symbols.Symbol,
    ) []const u8 {
        switch (function_symbol.kind) {
            .Function => |function_info| switch (function_info.implementation) {
                .BuiltinPrintInt => return runtime.runtime_print_int_function_name,
                .BuiltinPrintString => return runtime.runtime_print_string_function_name,
                .BuiltinReadFile => return runtime.runtime_read_file_function_name,
                .BuiltinReadLine => return runtime.runtime_read_line_function_name,
                .BuiltinGetArguments => return runtime.runtime_get_arguments_function_name,
                .UserDefined => {
                    return std.fmt.allocPrint(
                        self.allocator,
                        "matcha_function_{d}_{s}",
                        .{ function_symbol.id, function_symbol.name },
                    ) catch unreachable;
                },
            },
            else => unreachable,
        }
    }

    pub fn generateStructureName(self: *@This(), symbol: symbols.Symbol) []const u8 {
        switch (symbol.kind) {
            .Structure => return std.fmt.allocPrint(
                self.allocator,
                "matcha_structure_{d}_{s}",
                .{ symbol.id, symbol.name },
            ) catch unreachable,
            else => unreachable,
        }
    }
};
