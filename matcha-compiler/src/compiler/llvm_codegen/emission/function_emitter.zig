const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const runtime_call_emitter_module = @import("runtime_call_emitter.zig");
const function_ir_builder_module = @import("function_ir_builder.zig");
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");

const Label = function_symbol_generator_module.Label;
const FunctionIrBuilder = function_ir_builder_module.FunctionIrBuilder;
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_call_emitter_module.RuntimeCallEmitter;
const NodeEmitter = node_emitter_module.NodeEmitter;
const Environment = node_emitter_module.Environment;

pub const FunctionEmitter = struct {
    arena: std.mem.Allocator,
    function_symbol_generator: *FunctionSymbolGenerator,
    function_ir_builder: *FunctionIrBuilder,
    runtime_call_emitter: *RuntimeCallEmitter,
    node_emitter: *NodeEmitter,

    pub fn init(
        arena: std.mem.Allocator,
        function_symbol_generator: *FunctionSymbolGenerator,
        function_ir_builder: *FunctionIrBuilder,
        runtime_call_emitter: *RuntimeCallEmitter,
        node_emitter: *NodeEmitter,
    ) @This() {
        return .{
            .arena = arena,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = function_ir_builder,
            .runtime_call_emitter = runtime_call_emitter,
            .node_emitter = node_emitter,
        };
    }

    pub fn emitMainFunction(self: *@This(), lowered_program: *const lowering.LoweredProgram) ![]const u8 {
        self.resetCurrentFunctionState();

        var environment = Environment.init(self.arena, null, lowered_program.analyzed_program.type_store.integer_type_id);

        // Boehm GC asks portable programs to initialize it at start-up, before the first allocation.
        try self.runtime_call_emitter.emitInitiateGarbageCollectorCall(self.function_ir_builder);
        try self.runtime_call_emitter.emitInitializeArgumentsCall(self.function_ir_builder);

        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .item_definition => continue,
                else => {},
            }

            _ = try self.node_emitter.emitNode(statement, lowered_program, &environment);
        }

        try self.function_ir_builder.emitTerminatorInstruction("ret i32 0");

        return self.renderCurrentFunction("main", "i32", "i32 %parameter.argc, ptr %parameter.argv");
    }

    pub fn emitFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.FunctionDefinition,
        lowered_program: *const lowering.LoweredProgram,
    ) ![]const u8 {
        self.resetCurrentFunctionState();

        const function_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(function_node_id) orelse unreachable;
        const function_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_symbol_information = switch (function_symbol.kind) {
            .function => |function_symbol_information| function_symbol_information,
            else => unreachable,
        };
        const function_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_type_id = switch (lowered_program.analyzed_program.type_store.getType(function_type_id)) {
            .function => |function_type| function_type.return_type_id,
            else => unreachable,
        };
        const function_layout = lowered_program.function_layout_by_symbol_id.get(function_symbol_id) orelse unreachable;

        var parameter_list_buffer = std.ArrayList(u8){};
        var environment = Environment.init(self.arena, null, function_return_type_id);

        for (function_symbol_information.parameter_symbol_ids, 0..) |parameter_symbol_id, index| {
            const parameter_index = switch (function_layout.parameter_index_kind_by_definition_index[index]) {
                .absent => continue,
                .index => |parameter_index| parameter_index,
            };

            const parameter_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(parameter_symbol_id);
            const parameter_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = lowered_program.getLlvmIrType(parameter_type_id);
            const parameter_value = try self.function_symbol_generator.parameterName(parameter_symbol.name);

            if (parameter_index > 0) {
                try parameter_list_buffer.writer(self.arena).print(", ", .{});
            }
            try parameter_list_buffer.writer(self.arena).print(
                "{s} {s}",
                .{ parameter_llvm_ir_type, parameter_value },
            );

            const address = try self.function_symbol_generator.generateBindingAddressName(parameter_symbol.name);
            try self.function_ir_builder.emitStackAllocation(address, parameter_llvm_ir_type);
            try self.function_ir_builder.emitStore(parameter_value, address, parameter_llvm_ir_type);
            try environment.address_by_symbol_id.put(parameter_symbol_id, address);
        }

        const body_value = try self.node_emitter.emitNode(
            function_definition.body_expression,
            lowered_program,
            &environment,
        );

        const function_return_llvm_ir_type = switch (function_layout.return_type_value_kind) {
            .present => lowered_program.getLlvmIrType(function_return_type_id),
            .absent => "void",
        };

        if (self.function_ir_builder.currentLabel() != null) {
            switch (function_layout.return_type_value_kind) {
                .absent => try self.function_ir_builder.emitTerminatorInstruction("ret void"),
                .present => {
                    const return_instruction = try std.fmt.allocPrint(
                        self.arena,
                        "ret {s} {s}",
                        .{ function_return_llvm_ir_type, body_value.expectValue() },
                    );
                    try self.function_ir_builder.emitTerminatorInstruction(return_instruction);
                },
            }
        }

        return self.renderCurrentFunction(
            function_layout.llvm_function_name,
            function_return_llvm_ir_type,
            parameter_list_buffer.items,
        );
    }

    fn resetCurrentFunctionState(self: *@This()) void {
        self.function_symbol_generator.reset();
        self.function_ir_builder.reset();
    }

    fn renderCurrentFunction(
        self: *@This(),
        function_name: []const u8,
        return_llvm_ir_type: []const u8,
        parameter_list: []const u8,
    ) ![]const u8 {
        return self.function_ir_builder.render(function_name, return_llvm_ir_type, parameter_list);
    }
};
