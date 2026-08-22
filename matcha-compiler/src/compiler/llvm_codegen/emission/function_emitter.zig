const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const runtime_call_emitter_module = @import("runtime_call_emitter.zig");
const function_ir_builder_module = @import("function_ir_builder.zig");
const function_symbol_generator_module = @import("function_symbol_generator.zig");
const symbol_generator_module = @import("symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");

const Label = function_symbol_generator_module.Label;
const FunctionIrBuilder = function_ir_builder_module.FunctionIrBuilder;
const FunctionSymbolGenerator = function_symbol_generator_module.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_call_emitter_module.RuntimeCallEmitter;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const NodeEmitter = node_emitter_module.NodeEmitter;
const Environment = node_emitter_module.Environment;

pub const FunctionEmitter = struct {
    allocator: std.mem.Allocator,
    function_symbol_generator: *FunctionSymbolGenerator,
    function_ir_builder: *FunctionIrBuilder,
    symbol_generator: *SymbolGenerator,
    runtime_call_emitter: *const RuntimeCallEmitter,
    node_emitter: *NodeEmitter,

    pub fn init(
        allocator: std.mem.Allocator,
        function_symbol_generator: *FunctionSymbolGenerator,
        function_ir_builder: *FunctionIrBuilder,
        symbol_generator: *SymbolGenerator,
        runtime_call_emitter: *const RuntimeCallEmitter,
        node_emitter: *NodeEmitter,
    ) @This() {
        return .{
            .allocator = allocator,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = function_ir_builder,
            .symbol_generator = symbol_generator,
            .runtime_call_emitter = runtime_call_emitter,
            .node_emitter = node_emitter,
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn emitMainFunction(self: *@This(), lowered_program: *const lowering.LoweredProgram) []const u8 {
        self.resetCurrentFunctionState();

        var environment = Environment.init(self.allocator, null, lowered_program.analyzed_program.type_store.integer_type_id);
        defer environment.deinit();

        self.runtime_call_emitter.emitInitializeArgumentsCall(self.function_ir_builder);

        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => continue,
                else => {},
            }

            _ = self.node_emitter.emitNode(statement, lowered_program, &environment);
        }

        self.function_ir_builder.emitTerminatorInstruction("ret i32 0");

        return self.renderCurrentFunction("main", "i32", "i32 %argc, ptr %argv");
    }

    pub fn emitFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_function: *const symbols.ResolvedFunction,
        owning_structure_symbol: ?symbols.Symbol,
        lowered_program: *const lowering.LoweredProgram,
    ) []const u8 {
        self.resetCurrentFunctionState();

        const function_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(function_node_id) orelse unreachable;
        const function_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_type_id = lowered_program.analyzed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_type_id = switch (lowered_program.analyzed_program.type_store.getType(function_type_id)) {
            .Function => |id| lowered_program.analyzed_program.type_store.function_types.items[id].return_type,
            else => unreachable,
        };
        const function_layout = lowered_program.function_layout_by_symbol_id.get(function_symbol_id) orelse unreachable;

        var parameter_list_buffer = std.ArrayList(u8){};
        defer parameter_list_buffer.deinit(self.allocator);
        var environment = Environment.init(self.allocator, null, function_return_type_id);
        defer environment.deinit();

        for (resolved_function.parameters, 0..) |parameter, index| {
            const parameter_index = switch (function_layout.parameter_index_by_definition_index[index]) {
                .Absent => continue,
                .Index => |parameter_index| parameter_index,
            };

            const parameter_type_id = lowered_program.analyzed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = lowered_program.getLlvmIrType(parameter_type_id);
            const parameter_register = std.fmt.allocPrint(
                self.allocator,
                "%arg_{d}_{s}",
                .{ parameter_index, parameter.name },
            ) catch unreachable;

            if (parameter_index > 0) {
                parameter_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            parameter_list_buffer.writer(self.allocator).print(
                "{s} {s}",
                .{ parameter_llvm_ir_type, parameter_register },
            ) catch unreachable;

            // TODO: wtf was this for again?
            const storage = self.function_symbol_generator.generateStorage();
            self.function_ir_builder.emitAlloca(storage, parameter_llvm_ir_type);
            self.function_ir_builder.emitStore(parameter_register, storage, parameter_llvm_ir_type);
            environment.storage_by_symbol_id.put(parameter.symbol_id, storage) catch unreachable;
        }

        const body_register = self.node_emitter.emitNode(
            function_definition.body_expression,
            lowered_program,
            &environment,
        );

        const function_return_llvm_ir_type = switch (function_layout.runtime_return_kind) {
            .Present => lowered_program.getLlvmIrType(function_return_type_id),
            .Absent => "void",
        };

        if (self.function_ir_builder.currentLabel() != null) {
            switch (function_layout.runtime_return_kind) {
                .Absent => self.function_ir_builder.emitTerminatorInstruction("ret void"),
                .Present => {
                    const return_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "ret {s} {s}",
                        .{ function_return_llvm_ir_type, body_register.expectRegister() },
                    ) catch unreachable;
                    self.function_ir_builder.emitTerminatorInstruction(return_instruction);
                },
            }
        }

        return self.renderCurrentFunction(
            if (owning_structure_symbol) |structure_symbol|
                self.symbol_generator.generateStructureFunctionName(structure_symbol, function_symbol)
            else
                self.symbol_generator.generateFunctionName(function_symbol),
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
    ) []const u8 {
        return self.function_ir_builder.render(function_name, return_llvm_ir_type, parameter_list);
    }
};
