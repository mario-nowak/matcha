const std = @import("std");
const lowering = @import("lowering");
const ast = @import("ast");

const function_ir_builder_module = @import("function_ir_builder.zig");
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const string_literal_pool_module = @import("string_literal_pool.zig");

const Value = function_symbol_generator_module.Value;
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
    ) Value {
        const string_literal_global = string_literal_pool.registerLiteral(node_id, content);
        const pointer_value = self.emitStringLiteralPointer(
            string_literal_global.name,
            string_literal_global.len,
            function_symbol_generator,
            builder,
        );
        return self.emitStringValue(
            pointer_value,
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
    ) Value {
        const pointer_value = function_symbol_generator.generateValueName();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [{d} x i8], ptr {s}, i64 0, i64 0",
            .{ pointer_value, len, global_name },
        ) catch unreachable;
        builder.emitInstruction(pointer_instruction);

        return pointer_value;
    }

    fn emitStringValue(
        self: *@This(),
        pointer_value: Value,
        len: usize,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Value {
        const partial_string_value = function_symbol_generator.generateValueName();
        const partial_string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue {s} undef, ptr {s}, 0",
            .{ partial_string_value, lowering.llvm_type.string_llvm_type, pointer_value },
        ) catch unreachable;
        builder.emitInstruction(partial_string_instruction);

        const string_value = function_symbol_generator.generateValueName();
        const string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue {s} {s}, i64 {d}, 1",
            .{ string_value, lowering.llvm_type.string_llvm_type, partial_string_value, len },
        ) catch unreachable;
        builder.emitInstruction(string_instruction);

        return string_value;
    }
};
