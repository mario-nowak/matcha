const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const semantic_analysis = @import("semantic_analysis");

const function_emission = @import("function_emission");
const llvm_type_lowering = @import("llvm_type_lowering.zig");
const runtime_emission = @import("runtime_emission");
const symbol_generator_module = @import("symbol_generator.zig");
const string_literal_emitter_module = @import("string_literal_emitter.zig");
const structure_type_definition_emitter = @import("structure_type_definition_emitter.zig");

const Register = function_emission.Register;
const Label = function_emission.Label;
const Storage = function_emission.Storage;
const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_emission.RuntimeCallEmitter;
const RuntimeRequirements = runtime_emission.RuntimeRequirements;
const RuntimeSymbolEmitter = runtime_emission.RuntimeSymbolEmitter;
const RuntimeStringParts = runtime_emission.RuntimeStringParts;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const StringLiteralEmitter = string_literal_emitter_module.StringLiteralEmitter;
const StructureTypeDefinitionEmitter = structure_type_definition_emitter.StructureTypeDefinitionEmitter;
const llvmIrType = llvm_type_lowering.llvmIrType;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);

// A string is a header containing a pointer to the data and the length.
const llvm_string_type_definition = "%String = type { i8*, i64 }";
// An array is a header containing the length, capacity, and a pointer to the data.
const llvm_array_type_definition = "%Array = type { i64, i64, ptr }";

const LlvmTypeDefinition = struct {
    name: []const u8,
    types: []const u8,
};

const LoopContext = struct {
    continue_label: Label,
    leave_label: Label,
};

const LoopConstruct = struct {
    condition: ?*ast.Node,
    update: ?*ast.Node,
    body_block: *ast.Block,
};

const DecisionConstruct = struct {
    subject: ?*const ast.Node,
    arms: []const DecisionArm,
    else_arm: ?*const ast.Node,
    exhaustive_without_else: bool = false,
};

const DecisionArm = struct {
    condition: *const ast.Node,
    body: *const ast.Node,
};

const DecisionLabelNames = struct {
    arm: []const u8,
    else_arm: []const u8,
    next: []const u8,
    continue_label: []const u8,
};

const PhiIncoming = struct {
    label: Label,
    register: Register,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,
    function_return_type_id: typing.TypeId,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
        function_return_type_id: typing.TypeId,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
            .function_return_type_id = function_return_type_id,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.storage_by_symbol_id.deinit();
    }
};

pub const EmissionResult = struct {
    register: ?Register,
    exit_label: ?Label,
};

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    target_triple: []const u8,
    function_symbol_generator: FunctionSymbolGenerator,
    function_ir_builder: FunctionIrBuilder,
    symbol_generator: SymbolGenerator,
    runtime_call_emitter: RuntimeCallEmitter,
    runtime_symbol_emitter: RuntimeSymbolEmitter,
    string_literal_emitter: StringLiteralEmitter,
    structure_type_definition_emitter: StructureTypeDefinitionEmitter,
    llvm_matcha_type_by_type_id: std.AutoHashMap(typing.TypeId, LlvmTypeDefinition),
    runtime_requirements: RuntimeRequirements,

    pub fn init(
        allocator: std.mem.Allocator,
        target_triple: []const u8,
        function_symbol_generator: FunctionSymbolGenerator,
        builder: FunctionIrBuilder,
        symbol_generator: SymbolGenerator,
        runtime_call_emitter: RuntimeCallEmitter,
        runtime_symbol_emitter: RuntimeSymbolEmitter,
        string_literal_emitter: StringLiteralEmitter,
        structure_type_emitter: StructureTypeDefinitionEmitter,
    ) @This() {
        return .{
            .allocator = allocator,
            .target_triple = target_triple,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = builder,
            .symbol_generator = symbol_generator,
            .runtime_call_emitter = runtime_call_emitter,
            .runtime_symbol_emitter = runtime_symbol_emitter,
            .string_literal_emitter = string_literal_emitter,
            .structure_type_definition_emitter = structure_type_emitter,
            .llvm_matcha_type_by_type_id = std.AutoHashMap(typing.TypeId, LlvmTypeDefinition).init(allocator),
            .runtime_requirements = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.function_ir_builder.deinit();
        self.string_literal_emitter.deinit();
        self.llvm_matcha_type_by_type_id.deinit();
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const semantic_analysis.AnalyzedProgram) []const u8 {
        self.resetModuleState();

        const structure_type_definitions = self.structure_type_definition_emitter.emitStructureTypeDefinitions(typed_program);
        var user_defined_functions = self.emitTopLevelFunctionDefinitions(typed_program);
        defer user_defined_functions.deinit(self.allocator);
        var structure_method_functions = self.emitStructureMethodFunctionDefinitions(typed_program);
        defer structure_method_functions.deinit(self.allocator);
        const main_function_ir = self.emitMainFunction(typed_program);

        return self.renderModule(
            structure_type_definitions,
            user_defined_functions.items,
            structure_method_functions.items,
            main_function_ir,
        );
    }

    fn emitTopLevelFunctionDefinitions(
        self: *@This(),
        typed_program: *const semantic_analysis.AnalyzedProgram,
    ) std.ArrayList([]const u8) {
        var user_defined_functions = std.ArrayList([]const u8){};
        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function_definition| {
                        const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(
                            statement.id,
                        ) orelse unreachable;
                        const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(
                            function_symbol_id,
                        ) orelse unreachable;
                        const function_ir = self.emitFunctionDefinition(
                            statement.id,
                            &function_definition,
                            &resolved_function,
                            null,
                            typed_program,
                        );
                        user_defined_functions.append(self.allocator, function_ir) catch unreachable;
                    },
                    .Structure => {},
                },
                else => {},
            }
        }

        return user_defined_functions;
    }

    fn renderModule(
        self: *@This(),
        user_defined_types: []const u8,
        user_defined_functions: []const []const u8,
        structure_method_functions: []const []const u8,
        main_function_ir: []const u8,
    ) []const u8 {
        var sections = std.ArrayList([]const u8){};
        defer sections.deinit(self.allocator);
        sections.append(self.allocator, self.renderModulePreamble()) catch unreachable;
        if (user_defined_types.len > 0) {
            sections.append(self.allocator, user_defined_types) catch unreachable;
        }
        for (user_defined_functions) |function_ir| {
            sections.append(self.allocator, function_ir) catch unreachable;
        }
        for (structure_method_functions) |function_ir| {
            sections.append(self.allocator, function_ir) catch unreachable;
        }
        sections.append(self.allocator, main_function_ir) catch unreachable;

        var module_buffer = std.ArrayList(u8){};
        defer module_buffer.deinit(self.allocator);
        for (sections.items, 0..) |section, index| {
            module_buffer.writer(self.allocator).print("{s}", .{section}) catch unreachable;
            if (index + 1 < sections.items.len) {
                module_buffer.writer(self.allocator).print("\n\n", .{}) catch unreachable;
            }
        }
        module_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;

        return std.fmt.allocPrint(self.allocator, "{s}", .{module_buffer.items}) catch unreachable;
    }

    fn resetModuleState(self: *@This()) void {
        self.runtime_requirements.reset();
        self.string_literal_emitter.resetModuleState();
    }

    fn renderModulePreamble(self: *@This()) []const u8 {
        var module_preamble_buffer = std.ArrayList(u8){};
        defer module_preamble_buffer.deinit(self.allocator);

        const runtime_symbol_declarations = self.runtime_symbol_emitter.emitDeclarations(self.runtime_requirements);
        module_preamble_buffer.writer(self.allocator).print(
            "target triple = \"{s}\"\n\n{s}\n\n{s}\n{s}",
            .{ self.target_triple, runtime_symbol_declarations, llvm_string_type_definition, llvm_array_type_definition },
        ) catch unreachable;

        const string_literal_globals_ir = self.string_literal_emitter.renderGlobals();
        if (string_literal_globals_ir.len > 0) {
            module_preamble_buffer.writer(self.allocator).print("\n\n{s}", .{string_literal_globals_ir}) catch unreachable;
        }
        return std.fmt.allocPrint(self.allocator, "{s}", .{module_preamble_buffer.items}) catch unreachable;
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

    fn emitMainFunction(self: *@This(), typed_program: *const semantic_analysis.AnalyzedProgram) []const u8 {
        self.resetCurrentFunctionState();

        var environment = Environment.init(self.allocator, null, typed_program.type_store.integer_type_id);
        defer environment.deinit();
        var current_label: Label = "entry";

        self.runtime_call_emitter.emitInitializeArgumentsCall(&self.function_ir_builder);

        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => continue,
                else => {},
            }

            const result = self.emitNode(statement, current_label, typed_program, &environment);
            if (result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                break;
            }
        }

        self.function_ir_builder.emitInstruction("ret i32 0");

        return self.renderCurrentFunction("main", "i32", "i32 %argc, ptr %argv");
    }

    fn emitFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_function: *const symbols.ResolvedFunction,
        owning_structure_symbol: ?symbols.Symbol,
        typed_program: *const semantic_analysis.AnalyzedProgram,
    ) []const u8 {
        self.resetCurrentFunctionState();

        const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(function_node_id) orelse unreachable;
        const function_symbol = typed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_type_id = typed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_type_id = switch (typed_program.type_store.getType(function_type_id)) {
            .Function => |id| typed_program.type_store.function_types.items[id].return_type,
            else => unreachable,
        };
        const function_return_llvm_ir_type = llvmIrType(&typed_program.type_store, function_return_type_id);

        var parameter_list_buffer = std.ArrayList(u8){};
        defer parameter_list_buffer.deinit(self.allocator);
        var environment = Environment.init(self.allocator, null, function_return_type_id);
        defer environment.deinit();

        for (resolved_function.parameters, 0..) |parameter, index| {
            const parameter_type_id = typed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = llvmIrType(&typed_program.type_store, parameter_type_id);
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

        const body_result = self.emitNode(
            function_definition.body_expression,
            "entry",
            typed_program,
            &environment,
        );

        if (body_result.exit_label != null) {
            switch (typed_program.type_store.getType(function_return_type_id)) {
                .Unit => {
                    self.function_ir_builder.emitInstruction("ret void");
                },
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

    fn emitStringParts(self: *@This(), string_register: Register) RuntimeStringParts {
        const pointer_register = self.function_symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 0",
            .{ pointer_register, string_register },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(pointer_instruction);

        const length_register = self.function_symbol_generator.generateRegister();
        const length_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 1",
            .{ length_register, string_register },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(length_instruction);

        return .{
            .pointer_register = pointer_register,
            .length_register = length_register,
        };
    }

    fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        switch (node.kind) {
            .Return => |return_statement| {
                if (return_statement.value) |return_value| {
                    const value_result = self.emitNode(
                        return_value,
                        entry_label,
                        typed_program,
                        environment,
                    );
                    if (value_result.exit_label == null) {
                        return .{
                            .exit_label = null,
                            .register = null,
                        };
                    }

                    const return_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "ret {s} {s}",
                        .{
                            llvmIrType(&typed_program.type_store, environment.function_return_type_id),
                            value_result.register.?,
                        },
                    ) catch unreachable;
                    self.function_ir_builder.emitInstruction(return_instruction);
                } else {
                    self.function_ir_builder.emitInstruction("ret void");
                }

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .IntegerLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = std.fmt.allocPrint(
                        self.allocator,
                        "{d}",
                        .{token.kind.IntLiteral},
                    ) catch unreachable,
                };
            },
            .BooleanLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = if (token.kind.BooleanLiteral) "1" else "0",
                };
            },
            .StringLiteral => |token| return .{
                .exit_label = entry_label,
                .register = self.string_literal_emitter.emitStringLiteralValue(
                    node.id,
                    token.kind.StringLiteral,
                    &self.function_symbol_generator,
                    &self.function_ir_builder,
                ),
            },
            .UnitLiteral => unreachable,
            .Identifier => {
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const llvm_ir_type = llvmIrType(
                    &typed_program.type_store,
                    typed_program.type_by_node_id.get(node.id).?,
                );
                const register = self.function_symbol_generator.generateRegister();
                self.function_ir_builder.emitLoad(register, storage, llvm_ir_type);

                return .{
                    .exit_label = entry_label,
                    .register = register,
                };
            },
            .Loop => |loop| {
                var body_block = switch (loop.body_block.kind) {
                    .Block => |block| block,
                    else => unreachable,
                };

                const loop_construct = LoopConstruct{
                    .condition = null,
                    .body_block = &body_block,
                    .update = null,
                };

                return self.emitLoopConstruct(
                    loop_construct,
                    typed_program,
                    environment,
                );
            },
            .While => |while_statement| {
                var body_block = switch (while_statement.body_block.kind) {
                    .Block => |block| block,
                    else => unreachable,
                };

                const loop_construct = LoopConstruct{
                    .condition = while_statement.condition,
                    .body_block = &body_block,
                    .update = while_statement.update,
                };

                return self.emitLoopConstruct(
                    loop_construct,
                    typed_program,
                    environment,
                );
            },
            .ForIn => |for_in| return self.emitForInArrayLoop(
                node,
                &for_in,
                entry_label,
                typed_program,
                environment,
            ),
            .Leave => {
                self.function_ir_builder.emitBranchInstruction(null, &.{environment.loop_context.?.leave_label});

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .Continue => {
                self.function_ir_builder.emitBranchInstruction(null, &.{environment.loop_context.?.continue_label});

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .CallExpression => |call_expression| {
                var structure_symbol_id: ?symbols.SymbolId = null;
                var instance_method_receiver: ?*const ast.Node = null;
                const callee_symbol_id = switch (call_expression.callee.kind) {
                    .MemberAccess => |callee_member_access| member_access_callee_symbol_id: {
                        const member_access = typed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable;
                        switch (member_access) {
                            .StructureInstanceMethodAccess => |structure_method| {
                                structure_symbol_id = structure_method.structure_symbol_id;
                                instance_method_receiver = callee_member_access.base;
                                break :member_access_callee_symbol_id structure_method.function_symbol_id;
                            },
                            .StructureTypeFunctionAccess => |structure_function| {
                                structure_symbol_id = structure_function.structure_symbol_id;
                                break :member_access_callee_symbol_id structure_function.function_symbol_id;
                            },
                            .ArrayInstanceMethodAccess => |array_method| {
                                return switch (array_method) {
                                    .Append => self.emitArrayAppendCall(
                                        &callee_member_access,
                                        &call_expression,
                                        entry_label,
                                        typed_program,
                                        environment,
                                    ),
                                };
                            },
                            .StringInstanceMethodAccess => |string_method| {
                                return self.emitStringMethodCall(
                                    string_method,
                                    &callee_member_access,
                                    &call_expression,
                                    entry_label,
                                    typed_program,
                                    environment,
                                );
                            },
                            .IntegerInstanceMethodAccess => |integer_method| {
                                return self.emitIntegerMethodCall(
                                    integer_method,
                                    &callee_member_access,
                                    &call_expression,
                                    entry_label,
                                    typed_program,
                                    environment,
                                );
                            },
                            else => unreachable,
                        }
                    },
                    else => typed_program.resolved_program.symbol_id_by_node_id.get(
                        call_expression.callee.id,
                    ) orelse unreachable,
                };
                const callee_symbol = typed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
                const function_info = switch (callee_symbol.kind) {
                    .Function => |function_info| function_info,
                    else => unreachable,
                };

                const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                var current_label = entry_label;
                var argument_registers = std.ArrayList(Register){};
                defer argument_registers.deinit(self.allocator);

                if (instance_method_receiver) |receiver| {
                    const receiver_result = self.emitNode(
                        receiver,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (receiver_result.exit_label) |exit_label| {
                        current_label = exit_label;
                    } else {
                        return .{
                            .exit_label = null,
                            .register = null,
                        };
                    }
                    argument_registers.append(
                        self.allocator,
                        receiver_result.register orelse unreachable,
                    ) catch unreachable;
                }

                for (call_expression.arguments) |*argument| {
                    const argument_result = self.emitNode(
                        argument,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (argument_result.exit_label) |exit_label| {
                        current_label = exit_label;
                    } else {
                        return .{
                            .exit_label = null,
                            .register = null,
                        };
                    }
                    argument_registers.append(
                        self.allocator,
                        argument_result.register orelse unreachable,
                    ) catch unreachable;
                }

                switch (function_info.implementation) {
                    .BuiltinPrintInt => self.runtime_requirements.print_int = true,
                    .BuiltinPrintString => {
                        self.runtime_requirements.print_string = true;
                        self.runtime_call_emitter.emitPrintStringCall(
                            &self.function_ir_builder,
                            self.emitStringParts(argument_registers.items[0]),
                        );

                        return .{
                            .exit_label = current_label,
                            .register = null,
                        };
                    },
                    .BuiltinReadFile => {
                        self.runtime_requirements.read_file = true;
                        const result_register = self.runtime_call_emitter.emitReadFileCall(
                            &self.function_ir_builder,
                            &self.function_symbol_generator,
                            self.emitStringParts(argument_registers.items[0]),
                        );

                        return .{
                            .exit_label = current_label,
                            .register = result_register,
                        };
                    },
                    .BuiltinReadLine => {
                        self.runtime_requirements.read_line = true;
                        const result_register = self.runtime_call_emitter.emitReadLineCall(
                            &self.function_ir_builder,
                            &self.function_symbol_generator,
                        );
                        return .{
                            .exit_label = current_label,
                            .register = result_register,
                        };
                    },
                    .BuiltinGetArguments => {
                        self.runtime_requirements.get_arguments = true;
                    },
                    .UserDefined => {},
                }

                var argument_list_buffer = std.ArrayList(u8){};
                defer argument_list_buffer.deinit(self.allocator);
                for (resolved_function.parameters, argument_registers.items, 0..) |parameter, argument_register, index| {
                    const parameter_type_id = typed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
                    if (index > 0) {
                        argument_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
                    }
                    argument_list_buffer.writer(self.allocator).print(
                        "{s} {s}",
                        .{
                            llvmIrType(&typed_program.type_store, parameter_type_id),
                            argument_register,
                        },
                    ) catch unreachable;
                }

                const function_name = if (structure_symbol_id) |owning_structure_symbol_id|
                    self.symbol_generator.generateStructureFunctionName(
                        typed_program.resolved_program.symbol_table.getSymbol(owning_structure_symbol_id),
                        callee_symbol,
                    )
                else
                    self.symbol_generator.generateFunctionName(callee_symbol);
                const function_type_id = typed_program.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                const function_return_type_id = switch (typed_program.type_store.getType(function_type_id)) {
                    .Function => |id| typed_program.type_store.function_types.items[id].return_type,
                    else => unreachable,
                };
                const function_return_llvm_ir_type = llvmIrType(&typed_program.type_store, function_return_type_id);
                if (function_return_type_id == typed_program.type_store.unit_type_id) {
                    const call_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "call {s} @{s}({s})",
                        .{ function_return_llvm_ir_type, function_name, argument_list_buffer.items },
                    ) catch unreachable;
                    self.function_ir_builder.emitInstruction(call_instruction);

                    return .{
                        .exit_label = current_label,
                        .register = null,
                    };
                }

                const result_register = self.function_symbol_generator.generateRegister();
                const call_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = call {s} @{s}({s})",
                    .{ result_register, function_return_llvm_ir_type, function_name, argument_list_buffer.items },
                ) catch unreachable;
                self.function_ir_builder.emitInstruction(call_instruction);

                return .{
                    .exit_label = current_label,
                    .register = result_register,
                };
            },
            .MemberAccess => |member_access| return self.emitMemberAccess(
                node,
                &member_access,
                entry_label,
                typed_program,
                environment,
            ),
            .BinaryExpression => |binary_expression| {
                const left_result = self.emitNode(
                    binary_expression.left,
                    entry_label,
                    typed_program,
                    environment,
                );
                const right_result = self.emitNode(
                    binary_expression.right,
                    left_result.exit_label.?,
                    typed_program,
                    environment,
                );
                const left_operand_type = typed_program.type_by_node_id.get(binary_expression.left.id).?;
                const result_register = self.emitBinaryOperation(
                    binary_expression.operator,
                    left_operand_type,
                    left_result.register.?,
                    right_result.register.?,
                    typed_program,
                );

                return .{
                    .exit_label = right_result.exit_label,
                    .register = result_register,
                };
            },
            .UnaryExpression => |unary_expression| {
                const operand_result = self.emitNode(
                    unary_expression.operand,
                    entry_label,
                    typed_program,
                    environment,
                );
                const result_register = self.function_symbol_generator.generateRegister();
                const operation_type = typed_program.type_by_node_id.get(node.id).?;
                const instruction_type = llvmIrType(&typed_program.type_store, operation_type);
                const instruction = switch (unary_expression.operator) {
                    .Negate => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = sub {s} 0, {s}",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                    .Not => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = xor {s} {s}, 1",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                };
                self.function_ir_builder.emitInstruction(instruction);

                return .{
                    .exit_label = operand_result.exit_label,
                    .register = result_register,
                };
            },
            .Declaration => |value_declaration| {
                const value_declaration_result = self.emitNode(
                    value_declaration.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const value_type_id = typed_program.type_by_node_id.get(value_declaration.value.id).?;
                const llvm_ir_type = llvmIrType(&typed_program.type_store, value_type_id);

                const storage = self.function_symbol_generator.generateStorage();
                self.function_ir_builder.emitAlloca(storage, llvm_ir_type);
                self.function_ir_builder.emitStore(value_declaration_result.register.?, storage, llvm_ir_type);

                environment.storage_by_symbol_id.put(symbol_id, storage) catch unreachable;

                return .{
                    .exit_label = value_declaration_result.exit_label,
                    .register = null,
                };
            },
            .Assignment => |assignment| {
                const place_result = self.emitPlace(
                    assignment.target,
                    entry_label,
                    typed_program,
                    environment,
                );
                if (place_result.exit_label == null) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                const value_type_id = typed_program.type_by_node_id.get(assignment.target.id).?;
                const llvm_ir_type = llvmIrType(&typed_program.type_store, value_type_id);
                switch (assignment.operator) {
                    .Assign => {
                        const value_result = self.emitNode(
                            assignment.value,
                            place_result.exit_label.?,
                            typed_program,
                            environment,
                        );
                        self.function_ir_builder.emitStore(value_result.register.?, place_result.register.?, llvm_ir_type);

                        return .{
                            .exit_label = value_result.exit_label,
                            .register = null,
                        };
                    },
                    .Compound => |binary_operator| {
                        const current_value_register = self.function_symbol_generator.generateRegister();
                        self.function_ir_builder.emitLoad(current_value_register, place_result.register.?, llvm_ir_type);

                        const value_result = self.emitNode(
                            assignment.value,
                            place_result.exit_label.?,
                            typed_program,
                            environment,
                        );
                        if (value_result.exit_label == null) {
                            return .{
                                .exit_label = null,
                                .register = null,
                            };
                        }

                        const result_register = self.emitBinaryOperation(
                            binary_operator,
                            value_type_id,
                            current_value_register,
                            value_result.register.?,
                            typed_program,
                        );

                        self.function_ir_builder.emitStore(result_register, place_result.register.?, llvm_ir_type);
                        return .{
                            .exit_label = value_result.exit_label,
                            .register = null,
                        };
                    },
                }
            },
            .Block => |block| return self.emitBlock(
                block,
                entry_label,
                typed_program,
                environment,
            ),
            .IfStatement => |if_statement| {
                const decision_arms = [_]DecisionArm{.{
                    .condition = if_statement.condition,
                    .body = if_statement.then_branch,
                }};
                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = null,
                        .arms = &decision_arms,
                        .else_arm = null,
                    },
                    .{
                        .arm = "then",
                        .else_arm = "else",
                        .next = "next",
                        .continue_label = "continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .IfExpression => |if_expression| {
                const decision_arms = [_]DecisionArm{.{
                    .condition = if_expression.condition,
                    .body = if_expression.then_block,
                }};
                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = null,
                        .arms = &decision_arms,
                        .else_arm = if_expression.else_block,
                    },
                    .{
                        .arm = "then",
                        .else_arm = "else",
                        .next = "next",
                        .continue_label = "continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .MatchExpression => |match_expression| {
                var decision_arms = std.ArrayList(DecisionArm){};
                defer decision_arms.deinit(self.allocator);
                for (match_expression.arms) |arm| {
                    decision_arms.append(self.allocator, .{
                        .condition = arm.pattern_or_condition,
                        .body = arm.body,
                    }) catch unreachable;
                }

                const exhaustive_without_else = if (match_expression.subject) |subject|
                    match_expression.else_arm == null and
                        typed_program.type_by_node_id.get(subject.id).? == typed_program.type_store.boolean_type_id
                else
                    false;

                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = match_expression.subject,
                        .arms = decision_arms.items,
                        .else_arm = match_expression.else_arm,
                        .exhaustive_without_else = exhaustive_without_else,
                    },
                    .{
                        .arm = "match_arm",
                        .else_arm = "match_else",
                        .next = "match_next",
                        .continue_label = "match_continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .ExpressionStatement => |expression_statement| {
                const emission_result = self.emitNode(
                    expression_statement.expression,
                    entry_label,
                    typed_program,
                    environment,
                );

                return .{
                    .exit_label = emission_result.exit_label,
                    .register = null,
                };
            },
            .ItemDefinition => {
                return .{
                    .exit_label = entry_label,
                    .register = null,
                };
            },
            .StructureConstruction => |structure_construction| return self.emitStructureConstruction(
                node,
                structure_construction.fields,
                entry_label,
                typed_program,
                environment,
            ),
            .AnonymousStructureLiteral => |anonymous_structure_literal| return self.emitStructureConstruction(
                node,
                anonymous_structure_literal.fields,
                entry_label,
                typed_program,
                environment,
            ),
            .ArrayLiteral => |array_literal| return self.emitArrayLiteral(
                node,
                &array_literal,
                entry_label,
                typed_program,
                environment,
            ),
            .IndexAccess => |index_access| return self.emitIndexAccess(
                node,
                &index_access,
                entry_label,
                typed_program,
                environment,
            ),
        }
    }

    fn emitBinaryOperation(
        self: *@This(),
        binary_operator: ast.BinaryOperator,
        operand_type_id: typing.TypeId,
        left_register: Register,
        right_register: Register,
        typed_program: *const semantic_analysis.AnalyzedProgram,
    ) Register {
        if (operand_type_id == typed_program.type_store.string_type_id) {
            return switch (binary_operator) {
                .Add => concatenate: {
                    self.runtime_requirements.string_concatenate = true;
                    break :concatenate self.runtime_call_emitter.emitStringConcatenateCall(
                        &self.function_ir_builder,
                        &self.function_symbol_generator,
                        self.emitStringParts(left_register),
                        self.emitStringParts(right_register),
                    );
                },
                .Equal => compare_equal: {
                    self.runtime_requirements.string_compare = true;
                    break :compare_equal self.runtime_call_emitter.emitStringCompareCall(
                        &self.function_ir_builder,
                        &self.function_symbol_generator,
                        self.emitStringParts(left_register),
                        self.emitStringParts(right_register),
                    );
                },
                .NotEqual => compare_not_equal: {
                    self.runtime_requirements.string_compare = true;
                    const equal_register = self.runtime_call_emitter.emitStringCompareCall(
                        &self.function_ir_builder,
                        &self.function_symbol_generator,
                        self.emitStringParts(left_register),
                        self.emitStringParts(right_register),
                    );
                    const result_register = self.function_symbol_generator.generateRegister();
                    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                        self.allocator,
                        "{s} = xor i1 {s}, 1",
                        .{ result_register, equal_register },
                    ) catch unreachable);
                    break :compare_not_equal result_register;
                },
                else => unreachable,
            };
        }

        const llvm_ir_type = llvmIrType(&typed_program.type_store, operand_type_id);
        const operator_instruction = switch (binary_operator) {
            .Add => "add",
            .Subtract => "sub",
            .Multiply => "mul",
            .Divide => "sdiv",
            .Equal => "icmp eq",
            .NotEqual => "icmp ne",
            .LessThan => "icmp slt",
            .LessThanOrEqual => "icmp sle",
            .GreaterThan => "icmp sgt",
            .GreaterThanOrEqual => "icmp sge",
            .And => "and",
            .Or => "or",
        };

        const result_register = self.function_symbol_generator.generateRegister();
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = {s} {s} {s}, {s}",
            .{ result_register, operator_instruction, llvm_ir_type, left_register, right_register },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(instruction);

        return result_register;
    }

    fn emitMemberAccess(
        self: *@This(),
        node: *const ast.Node,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const resolved_member_access = typed_program.member_access_by_node_id.get(node.id) orelse unreachable;
        switch (resolved_member_access) {
            .ArrayInstanceFieldAccess => |array_field| switch (array_field) {
                .Length => {
                    const base_result = self.emitNode(
                        member_access.base,
                        entry_label,
                        typed_program,
                        environment,
                    );
                    if (base_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }

                    const length_pointer_register = self.function_symbol_generator.generateRegister();
                    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                        self.allocator,
                        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
                        .{ length_pointer_register, base_result.register orelse unreachable },
                    ) catch unreachable);

                    const length_register = self.function_symbol_generator.generateRegister();
                    self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

                    return .{
                        .exit_label = base_result.exit_label,
                        .register = length_register,
                    };
                },
            },
            .StringInstanceFieldAccess => |string_field| switch (string_field) {
                .Length => {
                    const base_result = self.emitNode(
                        member_access.base,
                        entry_label,
                        typed_program,
                        environment,
                    );
                    if (base_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }

                    const string_parts = self.emitStringParts(base_result.register orelse unreachable);
                    return .{
                        .exit_label = base_result.exit_label,
                        .register = string_parts.length_register,
                    };
                },
            },
            .StructureInstanceFieldAccess => {
                const member_pointer_result = self.emitMemberAccessPointer(
                    node.id,
                    member_access,
                    entry_label,
                    typed_program,
                    environment,
                );
                if (member_pointer_result.exit_label == null) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                const member_register = self.function_symbol_generator.generateRegister();
                self.function_ir_builder.emitLoad(
                    member_register,
                    member_pointer_result.register.?,
                    llvmIrType(&typed_program.type_store, typed_program.type_by_node_id.get(node.id).?),
                );

                return .{
                    .exit_label = member_pointer_result.exit_label,
                    .register = member_register,
                };
            },
            .StructureInstanceMethodAccess => unreachable,
            .StructureTypeFunctionAccess => unreachable,
            .ArrayInstanceMethodAccess => unreachable,
            .StringInstanceMethodAccess => unreachable,
            .IntegerInstanceMethodAccess => unreachable,
        }
    }

    fn emitPlace(
        self: *@This(),
        target: *const ast.Node,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        switch (target.kind) {
            .Identifier => {
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(target.id).?;
                return .{
                    .exit_label = entry_label,
                    .register = environment.storage_by_symbol_id.get(symbol_id).?,
                };
            },
            .MemberAccess => |member_access| return self.emitMemberAccessPointer(
                target.id,
                &member_access,
                entry_label,
                typed_program,
                environment,
            ),
            .IndexAccess => |index_access| return self.emitIndexAccessPointer(
                &index_access,
                entry_label,
                typed_program,
                environment,
            ),
            else => unreachable,
        }
    }

    fn emitMemberAccessPointer(
        self: *@This(),
        node_id: ast.NodeId,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(
            member_access.base,
            entry_label,
            typed_program,
            environment,
        );
        if (base_result.exit_label == null) {
            return .{
                .exit_label = null,
                .register = null,
            };
        }

        const resolved_member_access = typed_program.member_access_by_node_id.get(node_id) orelse unreachable;
        const field_index = switch (resolved_member_access) {
            .StructureInstanceFieldAccess => |structure_field| structure_field.field_index,
            .StructureInstanceMethodAccess => unreachable,
            .ArrayInstanceFieldAccess => unreachable,
            .StructureTypeFunctionAccess => unreachable,
            .ArrayInstanceMethodAccess => unreachable,
            .StringInstanceFieldAccess => unreachable,
            .StringInstanceMethodAccess => unreachable,
            .IntegerInstanceMethodAccess => unreachable,
        };

        const base_type_id = typed_program.type_by_node_id.get(member_access.base.id) orelse unreachable;
        switch (typed_program.type_store.getType(base_type_id)) {
            .Structure => {},
            else => unreachable,
        }
        const structure_symbol = self.getStructureSymbolForTypeId(typed_program, base_type_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);

        const field_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ field_pointer_register, structure_llvm_type_name, base_result.register orelse unreachable, field_index },
        ) catch unreachable);

        return .{
            .exit_label = base_result.exit_label,
            .register = field_pointer_register,
        };
    }

    fn emitStructureConstruction(
        self: *@This(),
        node: *const ast.Node,
        fields: []const ast.StructureConstructionField,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const node_type_id = typed_program.type_by_node_id.get(node.id) orelse unreachable;
        const structure_symbol = self.getStructureSymbolForTypeId(typed_program, node_type_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);
        const structure_type_id = switch (typed_program.type_store.getType(node_type_id)) {
            .Structure => |id| id,
            else => unreachable,
        };
        const structure_type = typed_program.type_store.structure_types.items[structure_type_id];
        const structure_construction_layout = typed_program.structure_construction_layout_by_node_id.get(
            node.id,
        ) orelse unreachable;

        const memory_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(
            std.fmt.allocPrint(
                self.allocator,
                "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%{s}, ptr null, i32 1) to i64))",
                .{ memory_register, structure_llvm_type_name },
            ) catch unreachable,
        );

        var current_label: Label = entry_label;
        for (fields, structure_construction_layout.field_indices) |field, field_index| {
            const structure_field = structure_type.fields[@intCast(field_index)];
            const field_value_result = self.emitNode(
                field.value,
                current_label,
                typed_program,
                environment,
            );
            if (field_value_result.exit_label == null) {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
            current_label = field_value_result.exit_label.?;

            const field_pointer_register = self.function_symbol_generator.generateRegister();
            self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                self.allocator,
                "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
                .{ field_pointer_register, structure_llvm_type_name, memory_register, field_index },
            ) catch unreachable);

            const field_llvm_ir_type = llvmIrType(&typed_program.type_store, structure_field.type_id);
            self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                self.allocator,
                "store {s} {s}, ptr {s}",
                .{ field_llvm_ir_type, field_value_result.register orelse unreachable, field_pointer_register },
            ) catch unreachable);
        }

        return .{
            .exit_label = current_label,
            .register = memory_register,
        };
    }

    fn emitForInArrayLoop(
        self: *@This(),
        node: *const ast.Node,
        for_in: *const ast.ForIn,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const iterable_result = self.emitNode(
            for_in.iterable,
            entry_label,
            typed_program,
            environment,
        );
        if (iterable_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const iterable_type_id = typed_program.type_by_node_id.get(for_in.iterable.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(iterable_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        const item_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
        const item_storage = self.function_symbol_generator.generateStorage();
        self.function_ir_builder.emitAlloca(item_storage, element_llvm_type);
        environment.storage_by_symbol_id.put(item_symbol_id, item_storage) catch unreachable;

        const index_storage = self.function_symbol_generator.generateStorage();
        self.function_ir_builder.emitAlloca(index_storage, "i64");
        self.function_ir_builder.emitStore("0", index_storage, "i64");

        const length_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
            .{ length_pointer_register, iterable_result.register orelse unreachable },
        ) catch unreachable);

        const length_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

        const data_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
            .{ data_pointer_register, iterable_result.register orelse unreachable },
        ) catch unreachable);

        const data_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(data_register, data_pointer_register, "ptr");

        const loop_header_label = self.function_symbol_generator.generateLabel("loop_header");
        const loop_body_label = self.function_symbol_generator.generateLabel("loop_body");
        const loop_continue_label = self.function_symbol_generator.generateLabel("loop_continue");
        const loop_exit_label = self.function_symbol_generator.generateLabel("loop_exit");
        const previous_loop_context = environment.loop_context;
        const loop_context = LoopContext{
            .continue_label = loop_continue_label,
            .leave_label = loop_exit_label,
        };
        environment.loop_context = loop_context;

        self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
        self.function_ir_builder.emitLabel(loop_header_label);

        const current_index_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(current_index_register, index_storage, "i64");

        const within_bounds_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = icmp slt i64 {s}, {s}",
            .{ within_bounds_register, current_index_register, length_register },
        ) catch unreachable);
        self.function_ir_builder.emitBranchInstruction(within_bounds_register, &.{ loop_body_label, loop_exit_label });

        self.function_ir_builder.emitLabel(loop_body_label);

        const element_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
            .{ element_pointer_register, element_llvm_type, data_register, current_index_register },
        ) catch unreachable);

        const element_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(element_register, element_pointer_register, element_llvm_type);
        self.function_ir_builder.emitStore(element_register, item_storage, element_llvm_type);

        const body_block = switch (for_in.body_block.kind) {
            .Block => |block| block,
            else => unreachable,
        };
        const body_result = self.emitBlock(body_block, loop_body_label, typed_program, environment);

        if (body_result.exit_label != null) {
            self.function_ir_builder.emitBranchInstruction(null, &.{loop_continue_label});
        }
        self.function_ir_builder.emitLabel(loop_continue_label);

        const loop_index_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(loop_index_register, index_storage, "i64");
        const next_index_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = add i64 {s}, 1",
            .{ next_index_register, loop_index_register },
        ) catch unreachable);
        self.function_ir_builder.emitStore(next_index_register, index_storage, "i64");
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});

        self.function_ir_builder.emitLabel(loop_exit_label);
        environment.loop_context = previous_loop_context;

        return .{
            .exit_label = loop_exit_label,
            .register = null,
        };
    }

    fn emitArrayLiteral(
        self: *@This(),
        node: *const ast.Node,
        array_literal: *const ast.ArrayLiteral,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const array_type_id = typed_program.type_by_node_id.get(node.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(array_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);
        const length = array_literal.elements.len;

        const header_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))",
            .{header_register},
        ) catch unreachable);

        const data_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64))",
            .{ data_register, element_llvm_type, length },
        ) catch unreachable);

        var current_label: Label = entry_label;
        for (array_literal.elements, 0..) |*element, index| {
            const element_result = self.emitNode(element, current_label, typed_program, environment);
            if (element_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }
            current_label = element_result.exit_label.?;

            const element_pointer_register = self.function_symbol_generator.generateRegister();
            self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                self.allocator,
                "{s} = getelementptr inbounds {s}, ptr {s}, i64 {d}",
                .{ element_pointer_register, element_llvm_type, data_register, index },
            ) catch unreachable);

            self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                self.allocator,
                "store {s} {s}, ptr {s}",
                .{ element_llvm_type, element_result.register orelse unreachable, element_pointer_register },
            ) catch unreachable);
        }

        const length_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
            .{ length_pointer_register, header_register },
        ) catch unreachable);
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store i64 {d}, ptr {s}",
            .{ length, length_pointer_register },
        ) catch unreachable);

        const capacity_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 1",
            .{ capacity_pointer_register, header_register },
        ) catch unreachable);
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store i64 {d}, ptr {s}",
            .{ length, capacity_pointer_register },
        ) catch unreachable);

        const data_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
            .{ data_pointer_register, header_register },
        ) catch unreachable);
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store ptr {s}, ptr {s}",
            .{ data_register, data_pointer_register },
        ) catch unreachable);

        return .{
            .exit_label = current_label,
            .register = header_register,
        };
    }

    fn emitIndexAccess(
        self: *@This(),
        node: *const ast.Node,
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        _ = node;
        const pointer_result = self.emitIndexAccessPointer(
            index_access,
            entry_label,
            typed_program,
            environment,
        );
        if (pointer_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const base_type_id = typed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        const result_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(result_register, pointer_result.register orelse unreachable, element_llvm_type);

        return .{
            .exit_label = pointer_result.exit_label,
            .register = result_register,
        };
    }

    fn emitIndexAccessPointer(
        self: *@This(),
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(index_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const index_result = self.emitNode(index_access.index, base_result.exit_label.?, typed_program, environment);
        if (index_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const base_type_id = typed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        const length_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
            .{ length_pointer_register, base_result.register orelse unreachable },
        ) catch unreachable);

        const length_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

        const data_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
            .{ data_pointer_register, base_result.register orelse unreachable },
        ) catch unreachable);

        const data_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitLoad(data_register, data_pointer_register, "ptr");

        const negative_check_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = icmp slt i64 {s}, 0",
            .{ negative_check_register, index_result.register orelse unreachable },
        ) catch unreachable);

        const overflow_check_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = icmp sge i64 {s}, {s}",
            .{ overflow_check_register, index_result.register orelse unreachable, length_register },
        ) catch unreachable);

        const out_of_bounds_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = or i1 {s}, {s}",
            .{ out_of_bounds_register, negative_check_register, overflow_check_register },
        ) catch unreachable);

        const panic_label = self.function_symbol_generator.generateLabel("index_panic");
        const ok_label = self.function_symbol_generator.generateLabel("index_ok");
        self.function_ir_builder.emitBranchInstruction(out_of_bounds_register, &.{ panic_label, ok_label });

        self.function_ir_builder.emitLabel(panic_label);
        self.runtime_requirements.panic_index_out_of_bounds = true;
        const line = index_access.left_bracket.line;
        const column = index_access.left_bracket.column;
        self.runtime_call_emitter.emitPanicIndexOutOfBoundsCall(
            &self.function_ir_builder,
            line,
            column,
            index_result.register orelse unreachable,
            length_register,
        );
        self.function_ir_builder.emitInstruction("unreachable");

        self.function_ir_builder.emitLabel(ok_label);
        const element_pointer_register = self.function_symbol_generator.generateRegister();
        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
            .{ element_pointer_register, element_llvm_type, data_register, index_result.register orelse unreachable },
        ) catch unreachable);

        return .{
            .exit_label = ok_label,
            .register = element_pointer_register,
        };
    }

    fn emitArrayAppendCall(
        self: *@This(),
        callee_member_access: *const ast.MemberAccess,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        if (call_expression.arguments.len != 1) unreachable;

        self.runtime_requirements.array_append_slot = true;

        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const argument_result = self.emitNode(&call_expression.arguments[0], base_result.exit_label.?, typed_program, environment);
        if (argument_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const array_type_id = typed_program.type_by_node_id.get(callee_member_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(array_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        // The runtime helper grows the backing storage if needed and returns the slot for the new element.
        const slot_register = self.runtime_call_emitter.emitArrayAppendSlotCall(
            &self.function_ir_builder,
            &self.function_symbol_generator,
            base_result.register orelse unreachable,
            element_llvm_type,
        );

        self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ element_llvm_type, argument_result.register orelse unreachable, slot_register },
        ) catch unreachable);

        return .{
            .exit_label = argument_result.exit_label,
            .register = null,
        };
    }

    fn emitStringMethodCall(
        self: *@This(),
        string_method: typing.StringInstanceMethod,
        callee_member_access: *const ast.MemberAccess,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        return switch (string_method) {
            .Trim => {
                if (call_expression.arguments.len != 0) unreachable;
                self.runtime_requirements.string_trim = true;
                const result_register = self.runtime_call_emitter.emitStringTrimCall(
                    &self.function_ir_builder,
                    &self.function_symbol_generator,
                    self.emitStringParts(base_result.register orelse unreachable),
                );
                return .{
                    .exit_label = base_result.exit_label,
                    .register = result_register,
                };
            },
            .Split => {
                if (call_expression.arguments.len != 1) unreachable;
                self.runtime_requirements.string_split = true;

                const delimiter_result = self.emitNode(
                    &call_expression.arguments[0],
                    base_result.exit_label.?,
                    typed_program,
                    environment,
                );
                if (delimiter_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }

                const result_register = self.runtime_call_emitter.emitStringSplitCall(
                    &self.function_ir_builder,
                    &self.function_symbol_generator,
                    self.emitStringParts(base_result.register orelse unreachable),
                    self.emitStringParts(delimiter_result.register orelse unreachable),
                );

                return .{
                    .exit_label = delimiter_result.exit_label,
                    .register = result_register,
                };
            },
            .ToInt => {
                if (call_expression.arguments.len != 0) unreachable;
                self.runtime_requirements.string_to_int = true;

                const result_register = self.runtime_call_emitter.emitStringToIntCall(
                    &self.function_ir_builder,
                    &self.function_symbol_generator,
                    self.emitStringParts(base_result.register orelse unreachable),
                );

                return .{
                    .exit_label = base_result.exit_label,
                    .register = result_register,
                };
            },
        };
    }

    fn emitIntegerMethodCall(
        self: *@This(),
        integer_method: typing.IntegerInstanceMethod,
        callee_member_access: *const ast.MemberAccess,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        return switch (integer_method) {
            .ToString => {
                if (call_expression.arguments.len != 0) unreachable;
                self.runtime_requirements.int_to_string = true;

                const result_register = self.runtime_call_emitter.emitIntToStringCall(
                    &self.function_ir_builder,
                    &self.function_symbol_generator,
                    base_result.register orelse unreachable,
                );
                return .{
                    .exit_label = base_result.exit_label,
                    .register = result_register,
                };
            },
        };
    }

    fn getStructureSymbolForTypeId(
        self: *@This(),
        typed_program: *const semantic_analysis.AnalyzedProgram,
        type_id: typing.TypeId,
    ) symbols.Symbol {
        _ = self;

        var iterator = typed_program.type_by_symbol_id.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.* != type_id) {
                continue;
            }

            const symbol = typed_program.resolved_program.symbol_table.getSymbol(entry.key_ptr.*);
            switch (symbol.kind) {
                .Structure => return symbol,
                else => continue,
            }
        }

        unreachable;
    }

    fn emitStructureMethodFunctionDefinitions(
        self: *@This(),
        typed_program: *const semantic_analysis.AnalyzedProgram,
    ) std.ArrayList([]const u8) {
        var method_definitions = std.ArrayList([]const u8){};

        for (typed_program.resolved_program.program.statements) |*statement| {
            const structure_definition = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Structure => |structure| structure,
                    else => continue,
                },
                else => continue,
            };

            const structure_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(statement.id) orelse unreachable;
            const structure_symbol = typed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id);
            self.appendStructureMethodDefinitions(
                &method_definitions,
                structure_definition,
                structure_symbol,
                typed_program,
            );
        }

        return method_definitions;
    }

    fn appendStructureMethodDefinitions(
        self: *@This(),
        method_definitions: *std.ArrayList([]const u8),
        structure_definition: ast.Structure,
        structure_symbol: symbols.Symbol,
        typed_program: *const semantic_analysis.AnalyzedProgram,
    ) void {
        for (structure_definition.function_definitions) |function_definition_node| {
            const function_definition = switch (function_definition_node.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function| function,
                    else => unreachable,
                },
                else => unreachable,
            };
            const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(
                function_definition_node.id,
            ) orelse unreachable;
            const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(function_symbol_id) orelse unreachable;
            const function_definition_emission = self.emitFunctionDefinition(
                function_definition_node.id,
                &function_definition,
                &resolved_function,
                structure_symbol,
                typed_program,
            );
            method_definitions.append(self.allocator, function_definition_emission) catch unreachable;
        }
    }

    fn emitDecisionConstruct(
        self: *@This(),
        node: *const ast.Node,
        decision_construct: DecisionConstruct,
        label_names: DecisionLabelNames,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        var current_label = entry_label;
        var subject_register: ?Register = null;
        var subject_type_id: ?typing.TypeId = null;

        if (decision_construct.subject) |subject| {
            const subject_result = self.emitNode(subject, current_label, typed_program, environment);
            if (subject_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }
            current_label = subject_result.exit_label.?;
            subject_register = subject_result.register;
            subject_type_id = typed_program.type_by_node_id.get(subject.id).?;
        }

        const result_type_id = typed_program.type_by_node_id.get(node.id).?;
        const continue_label = self.function_symbol_generator.generateLabel(label_names.continue_label);
        var incoming_values = std.ArrayList(PhiIncoming){};
        defer incoming_values.deinit(self.allocator);
        var continue_reachable = false;

        const else_label = if (decision_construct.else_arm != null)
            self.function_symbol_generator.generateLabel(label_names.else_arm)
        else
            null;

        if (decision_construct.arms.len == 0 and decision_construct.else_arm != null) {
            const else_arm = decision_construct.else_arm.?;
            const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
            if (else_result.exit_label) |exit_label| {
                continue_reachable = true;
                if (result_type_id != typed_program.type_store.unit_type_id) {
                    incoming_values.append(self.allocator, .{
                        .label = exit_label,
                        .register = else_result.register.?,
                    }) catch unreachable;
                }
                self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
            } else {
                return .{ .exit_label = null, .register = null };
            }
        } else {
            for (decision_construct.arms, 0..) |arm, index| {
                const arm_label = self.function_symbol_generator.generateLabel(label_names.arm);
                const is_last_arm = index + 1 == decision_construct.arms.len;
                const false_branches_to_continue = is_last_arm and
                    else_label == null and
                    !decision_construct.exhaustive_without_else;
                const false_label = if (!is_last_arm)
                    self.function_symbol_generator.generateLabel(label_names.next)
                else if (else_label) |label|
                    label
                else if (decision_construct.exhaustive_without_else)
                    null
                else
                    continue_label;

                if (false_branches_to_continue) {
                    continue_reachable = true;
                }

                if (is_last_arm and decision_construct.exhaustive_without_else and else_label == null) {
                    self.function_ir_builder.emitBranchInstruction(null, &.{arm_label});
                } else if (decision_construct.subject != null) {
                    const pattern_result = self.emitNode(
                        arm.condition,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (pattern_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }
                    current_label = pattern_result.exit_label.?;

                    const comparison_register = self.emitBinaryOperation(
                        .Equal,
                        subject_type_id.?,
                        subject_register.?,
                        pattern_result.register.?,
                        typed_program,
                    );

                    self.function_ir_builder.emitBranchInstruction(comparison_register, &.{ arm_label, false_label.? });
                } else {
                    const condition_result = self.emitNode(
                        arm.condition,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (condition_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }
                    current_label = condition_result.exit_label.?;

                    self.function_ir_builder.emitBranchInstruction(condition_result.register.?, &.{ arm_label, false_label.? });
                }

                self.function_ir_builder.emitLabel(arm_label);
                const arm_result = self.emitNode(arm.body, arm_label, typed_program, environment);
                if (arm_result.exit_label) |exit_label| {
                    continue_reachable = true;
                    if (result_type_id != typed_program.type_store.unit_type_id) {
                        incoming_values.append(self.allocator, .{
                            .label = exit_label,
                            .register = arm_result.register.?,
                        }) catch unreachable;
                    }
                    self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
                }

                if (false_label) |next_label| {
                    if (!false_branches_to_continue) {
                        self.function_ir_builder.emitLabel(next_label);
                    }
                    current_label = next_label;
                } else {
                    current_label = arm_label;
                }
            }

            if (decision_construct.else_arm) |else_arm| {
                const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
                if (else_result.exit_label) |exit_label| {
                    continue_reachable = true;
                    if (result_type_id != typed_program.type_store.unit_type_id) {
                        incoming_values.append(self.allocator, .{
                            .label = exit_label,
                            .register = else_result.register.?,
                        }) catch unreachable;
                    }
                    self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
                }
            }
        }

        if (!continue_reachable) {
            return .{ .exit_label = null, .register = null };
        }

        self.function_ir_builder.emitLabel(continue_label);
        if (result_type_id == typed_program.type_store.unit_type_id) {
            return .{
                .exit_label = continue_label,
                .register = null,
            };
        }
        if (incoming_values.items.len == 0) {
            return .{ .exit_label = null, .register = null };
        }
        if (incoming_values.items.len == 1) {
            return .{
                .exit_label = continue_label,
                .register = incoming_values.items[0].register,
            };
        }

        var phi_incoming_buffer = std.ArrayList(u8){};
        defer phi_incoming_buffer.deinit(self.allocator);
        for (incoming_values.items, 0..) |incoming, index| {
            if (index > 0) {
                phi_incoming_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            phi_incoming_buffer.writer(self.allocator).print(
                "[{s}, %{s}]",
                .{ incoming.register, incoming.label },
            ) catch unreachable;
        }

        const result_register = self.function_symbol_generator.generateRegister();
        const phi_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = phi {s} {s}",
            .{
                result_register,
                llvmIrType(&typed_program.type_store, result_type_id),
                phi_incoming_buffer.items,
            },
        ) catch unreachable;
        self.function_ir_builder.emitInstruction(phi_instruction);

        return .{
            .exit_label = continue_label,
            .register = result_register,
        };
    }

    fn emitLoopConstruct(
        self: *@This(),
        loop_construct: LoopConstruct,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        const loop_header_label = self.function_symbol_generator.generateLabel("loop_header");
        const loop_body_label = self.function_symbol_generator.generateLabel("loop_body");
        const loop_continue_label = self.function_symbol_generator.generateLabel("loop_continue");
        const loop_exit_label = self.function_symbol_generator.generateLabel("loop_exit");
        const previous_loop_context = environment.loop_context;
        const loop_context = LoopContext{
            .continue_label = loop_continue_label,
            .leave_label = loop_exit_label,
        };
        environment.loop_context = loop_context;

        // Loop header
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
        self.function_ir_builder.emitLabel(loop_header_label);
        if (loop_construct.condition) |condition| {
            const condition_result = self.emitNode(
                condition,
                loop_header_label,
                typed_program,
                environment,
            );
            if (condition_result.exit_label == null) {
                environment.loop_context = previous_loop_context;
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
            self.function_ir_builder.emitBranchInstruction(condition_result.register.?, &.{ loop_body_label, loop_exit_label });
        } else {
            self.function_ir_builder.emitBranchInstruction(null, &.{loop_body_label});
        }

        // Loop body
        self.function_ir_builder.emitLabel(loop_body_label);
        const body_result = self.emitBlock(loop_construct.body_block.*, loop_body_label, typed_program, environment);

        // Loop continue
        if (body_result.exit_label != null) {
            self.function_ir_builder.emitBranchInstruction(null, &.{loop_continue_label});
        }
        self.function_ir_builder.emitLabel(loop_continue_label);
        if (loop_construct.update) |update| {
            const update_result = self.emitNode(update, loop_continue_label, typed_program, environment);
            if (update_result.exit_label != null) {
                self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
            }
        } else {
            self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
        }

        self.function_ir_builder.emitLabel(loop_exit_label);
        environment.loop_context = previous_loop_context;

        return .{
            .exit_label = loop_exit_label,
            .register = null,
        };
    }

    fn emitBlock(
        self: *@This(),
        block: ast.Block,
        entry_label: Label,
        typed_program: *const semantic_analysis.AnalyzedProgram,
        environment: *Environment,
    ) EmissionResult {
        var current_label = entry_label;
        for (block.statements) |statement| {
            const emission_result = self.emitNode(&statement, current_label, typed_program, environment);
            if (emission_result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
        }

        // Emit the result expression if it exists
        var result_register: ?Register = null;
        if (block.result) |result_node| {
            const emission_result = self.emitNode(result_node, current_label, typed_program, environment);
            result_register = emission_result.register;
            if (emission_result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
        }

        return .{
            .exit_label = current_label,
            .register = result_register,
        };
    }
};
