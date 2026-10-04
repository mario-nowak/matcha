const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;

pub const FunctionSymbolGenerator = struct {
    pub const generateValueName = struct {
        test "numbers values from zero" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const names = .{ try function_symbol_generator.generateValueName(), try function_symbol_generator.generateValueName() };

            try expect(names).toMatch(.{ "%value.0", "%value.1" });
        }
    };

    pub const generateBindingAddressName = struct {
        test "numbers binding addresses per name from zero" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const names = .{
                try function_symbol_generator.generateBindingAddressName("count"),
                try function_symbol_generator.generateBindingAddressName("total"),
                try function_symbol_generator.generateBindingAddressName("count"),
            };

            try expect(names).toMatch(.{ "%address.binding.count.0", "%address.binding.total.0", "%address.binding.count.1" });
        }
    };

    pub const generateSyntheticAddressName = struct {
        test "numbers synthetic addresses independently of binding addresses" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            _ = try function_symbol_generator.generateBindingAddressName("count");

            const names = .{ try function_symbol_generator.generateSyntheticAddressName(), try function_symbol_generator.generateSyntheticAddressName() };

            try expect(names).toMatch(.{ "%address.synthetic.0", "%address.synthetic.1" });
        }
    };

    pub const parameterName = struct {
        test "names a parameter after its name" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const name = try function_symbol_generator.parameterName("count");

            try expect(name).toMatch("%parameter.count");
        }
    };

    pub const generateConstructLabels = struct {
        test "numbers constructs per construct name from zero" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());

            const labels = .{
                try (try function_symbol_generator.generateConstructLabels("if")).role("end"),
                try (try function_symbol_generator.generateConstructLabels("match")).role("end"),
                try (try function_symbol_generator.generateConstructLabels("if")).role("end"),
            };

            try expect(labels).toMatch(.{ "if.0.end", "match.0.end", "if.1.end" });
        }

        test "names an arm and the condition of an arm by their index" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            const construct_labels = try function_symbol_generator.generateConstructLabels("match");

            const labels = .{ try construct_labels.arm(1), try construct_labels.armCondition(2) };

            try expect(labels).toMatch(.{ "match.0.arm.1", "match.0.arm.2.condition" });
        }
    };

    pub const reset = struct {
        test "restarts every counter" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            var function_symbol_generator = llvm_codegen.FunctionSymbolGenerator.init(arena.allocator());
            _ = try function_symbol_generator.generateValueName();
            _ = try function_symbol_generator.generateBindingAddressName("count");
            _ = try function_symbol_generator.generateSyntheticAddressName();
            _ = try function_symbol_generator.generateConstructLabels("if");

            function_symbol_generator.reset();

            const names = .{
                try function_symbol_generator.generateValueName(),
                try function_symbol_generator.generateBindingAddressName("count"),
                try function_symbol_generator.generateSyntheticAddressName(),
                try (try function_symbol_generator.generateConstructLabels("if")).role("end"),
            };
            try expect(names).toMatch(.{ "%value.0", "%address.binding.count.0", "%address.synthetic.0", "if.0.end" });
        }
    };
};
