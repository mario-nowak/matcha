const std = @import("std");
const ast = @import("ast");

const function_ir_builder_module = @import("function_ir_builder.zig");
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const string_literal_pool_module = @import("string_literal_pool.zig");

const Register = function_symbol_generator_module.Register;
const FunctionIrBuilder = function_ir_builder_module.FunctionIrBuilder;
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const StringLiteralPool = string_literal_pool_module.StringLiteralPool;

pub const StringLiteralEmitter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn emitStringLiteralValue(
        self: *@This(),
        string_literal_pool: *StringLiteralPool,
        node_id: ast.NodeId,
        content: []const u8,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const string_literal_global = string_literal_pool.intern(node_id, content);
        const pointer_register = self.emitStringLiteralPointer(
            string_literal_global.name,
            string_literal_global.len,
            function_symbol_generator,
            builder,
        );
        return self.emitStringValue(
            pointer_register,
            string_literal_global.len,
            function_symbol_generator,
            builder,
        );
    }

    fn emitStringLiteralPointer(
        self: *@This(),
        global_name: []const u8,
        len: usize,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const pointer_register = function_symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [{d} x i8], [{d} x i8]* {s}, i64 0, i64 0",
            .{ pointer_register, len, len, global_name },
        ) catch unreachable;
        builder.emitInstruction(pointer_instruction);

        return pointer_register;
    }

    fn emitStringValue(
        self: *@This(),
        pointer_register: Register,
        len: usize,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const partial_string_register = function_symbol_generator.generateRegister();
        const partial_string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String undef, i8* {s}, 0",
            .{ partial_string_register, pointer_register },
        ) catch unreachable;
        builder.emitInstruction(partial_string_instruction);

        const string_register = function_symbol_generator.generateRegister();
        const string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String {s}, i64 {d}, 1",
            .{ string_register, partial_string_register, len },
        ) catch unreachable;
        builder.emitInstruction(string_instruction);

        return string_register;
    }
};
