const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

pub const FunctionSymbolGenerator = struct {
    pub const generateValueName = struct {
        test "numbers values from zero" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const names = .{ function_symbol_generator.generateValueName(), function_symbol_generator.generateValueName() };

            try expect(names).toMatch(.{ "%value.0", "%value.1" });
        }
    };

    pub const generateBindingAddressName = struct {
        test "numbers binding addresses per name from zero" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const names = .{
                function_symbol_generator.generateBindingAddressName("count"),
                function_symbol_generator.generateBindingAddressName("total"),
                function_symbol_generator.generateBindingAddressName("count"),
            };

            try expect(names).toMatch(.{ "%address.binding.count.0", "%address.binding.total.0", "%address.binding.count.1" });
        }
    };

    pub const generateSyntheticAddressName = struct {
        test "numbers synthetic addresses independently of binding addresses" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            _ = function_symbol_generator.generateBindingAddressName("count");

            const names = .{ function_symbol_generator.generateSyntheticAddressName(), function_symbol_generator.generateSyntheticAddressName() };

            try expect(names).toMatch(.{ "%address.synthetic.0", "%address.synthetic.1" });
        }
    };

    pub const parameterName = struct {
        test "names a parameter after its name" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const name = function_symbol_generator.parameterName("count");

            try expect(name).toMatch("%parameter.count");
        }
    };

    pub const reset = struct {
        test "restarts every counter" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            _ = function_symbol_generator.generateValueName();
            _ = function_symbol_generator.generateBindingAddressName("count");
            _ = function_symbol_generator.generateSyntheticAddressName();

            function_symbol_generator.reset();

            const names = .{
                function_symbol_generator.generateValueName(),
                function_symbol_generator.generateBindingAddressName("count"),
                function_symbol_generator.generateSyntheticAddressName(),
            };
            try expect(names).toMatch(.{ "%value.0", "%address.binding.count.0", "%address.synthetic.0" });
        }
    };
};
