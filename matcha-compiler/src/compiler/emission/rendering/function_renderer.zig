const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const function_emission = @import("function_emission");
const runtime_emission = @import("runtime_emission");
const symbol_generator_module = @import("symbol_generator.zig");
const node_renderer_module = @import("node_renderer.zig");

const Label = function_emission.Label;
const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_emission.RuntimeCallEmitter;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const NodeRenderer = node_renderer_module.NodeRenderer;
const Environment = node_renderer_module.Environment;

pub const FunctionRenderer = struct {
    allocator: std.mem.Allocator,
    function_symbol_generator: *FunctionSymbolGenerator,
    function_ir_builder: *FunctionIrBuilder,
    symbol_generator: *SymbolGenerator,
    runtime_call_emitter: *const RuntimeCallEmitter,
    node_renderer: NodeRenderer,

    pub fn init(
        allocator: std.mem.Allocator,
        function_symbol_generator: *FunctionSymbolGenerator,
        function_ir_builder: *FunctionIrBuilder,
        symbol_generator: *SymbolGenerator,
        runtime_call_emitter: *const RuntimeCallEmitter,
        node_renderer: NodeRenderer,
    ) @This() {
        return .{
            .allocator = allocator,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = function_ir_builder,
            .symbol_generator = symbol_generator,
            .runtime_call_emitter = runtime_call_emitter,
            .node_renderer = node_renderer,
        };
    }

    pub fn emitMainFunction(self: *@This(), typed_program: *const lowering.LoweredProgram) []const u8 {
        self.resetCurrentFunctionState();

        var environment = Environment.init(self.allocator, null, typed_program.analyzed_program.type_store.integer_type_id);
        defer environment.deinit();
        var current_label: Label = "entry";

        self.runtime_call_emitter.emitInitializeArgumentsCall(self.function_ir_builder);

        for (typed_program.analyzed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => continue,
                else => {},
            }

            const result = self.node_renderer.emitNode(statement, current_label, typed_program, &environment);
            if (result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                break;
            }
        }

        self.function_ir_builder.emitInstruction("ret i32 0");

        return self.renderCurrentFunction("main", "i32", "i32 %argc, ptr %argv");
    }

    pub fn emitFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_function: *const symbols.ResolvedFunction,
        owning_structure_symbol: ?symbols.Symbol,
        typed_program: *const lowering.LoweredProgram,
    ) []const u8 {
        self.resetCurrentFunctionState();

        const function_symbol_id = typed_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(function_node_id) orelse unreachable;
        const function_symbol = typed_program.analyzed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_type_id = typed_program.analyzed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_type_id = switch (typed_program.analyzed_program.type_store.getType(function_type_id)) {
            .Function => |id| typed_program.analyzed_program.type_store.function_types.items[id].return_type,
            else => unreachable,
        };
        const function_return_llvm_ir_type = typed_program.llvmIrType(function_return_type_id);

        var parameter_list_buffer = std.ArrayList(u8){};
        defer parameter_list_buffer.deinit(self.allocator);
        var environment = Environment.init(self.allocator, null, function_return_type_id);
        defer environment.deinit();

        for (resolved_function.parameters, 0..) |parameter, index| {
            const parameter_type_id = typed_program.analyzed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = typed_program.llvmIrType(parameter_type_id);
            const parameter_register = std.fmt.allocPrint(
                self.allocator,
                "%arg_{d}_{s}",
                .{ index, parameter.name },
            ) catch unreachable;

            if (index > 0) {
                parameter_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            parameter_list_buffer.writer(self.allocator).print(
                "{s} {s}",
                .{ parameter_llvm_ir_type, parameter_register },
            ) catch unreachable;

            const storage = self.function_symbol_generator.generateStorage();
            self.function_ir_builder.emitAlloca(storage, parameter_llvm_ir_type);
            self.function_ir_builder.emitStore(parameter_register, storage, parameter_llvm_ir_type);
            environment.storage_by_symbol_id.put(parameter.symbol_id, storage) catch unreachable;
        }

        const body_result = self.node_renderer.emitNode(
            function_definition.body_expression,
            "entry",
            typed_program,
            &environment,
        );

        if (body_result.exit_label != null) {
            switch (typed_program.analyzed_program.type_store.getType(function_return_type_id)) {
                .Unit => self.function_ir_builder.emitInstruction("ret void"),
                else => {
                    const return_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "ret {s} {s}",
                        .{ function_return_llvm_ir_type, body_result.register orelse unreachable },
                    ) catch unreachable;
                    self.function_ir_builder.emitInstruction(return_instruction);
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
