const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const function_emission = @import("function_emission");
const runtime_emission = @import("runtime_emission");
const symbol_generator_module = @import("symbol_generator.zig");
const string_literal_renderer_module = @import("string_literal_renderer.zig");

const Register = function_emission.Register;
const Label = function_emission.Label;
const Storage = function_emission.Storage;
const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime_emission.RuntimeCallEmitter;
const RuntimeStringParts = runtime_emission.RuntimeStringParts;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const StringLiteralRenderer = string_literal_renderer_module.StringLiteralRenderer;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);

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

pub const NodeRenderer = struct {
    allocator: std.mem.Allocator,
    function_symbol_generator: *FunctionSymbolGenerator,
    function_ir_builder: *FunctionIrBuilder,
    symbol_generator: *SymbolGenerator,
    runtime_call_emitter: *const RuntimeCallEmitter,
    string_literal_renderer: *StringLiteralRenderer,

    pub fn init(
        allocator: std.mem.Allocator,
        function_symbol_generator: *FunctionSymbolGenerator,
        function_ir_builder: *FunctionIrBuilder,
        symbol_generator: *SymbolGenerator,
        runtime_call_emitter: *const RuntimeCallEmitter,
        string_literal_renderer: *StringLiteralRenderer,
    ) @This() {
        return .{
            .allocator = allocator,
            .function_symbol_generator = function_symbol_generator,
            .function_ir_builder = function_ir_builder,
            .symbol_generator = symbol_generator,
            .runtime_call_emitter = runtime_call_emitter,
            .string_literal_renderer = string_literal_renderer,
        };
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

    pub fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
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
                            typed_program.llvmIrType(environment.function_return_type_id),
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
                .register = self.string_literal_renderer.emitStringLiteralValue(
                    node.id,
                    token.kind.StringLiteral,
                    self.function_symbol_generator,
                    self.function_ir_builder,
                ),
            },
            .UnitLiteral => unreachable,
            .Identifier => {
                const symbol_id = typed_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const llvm_ir_type = typed_program.llvmIrType(
                    typed_program.analyzed_program.type_by_node_id.get(node.id).?,
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
            .CallExpression => |call_expression| return self.emitCallExpression(
                node,
                &call_expression,
                entry_label,
                typed_program,
                environment,
            ),
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
                const left_operand_type = typed_program.analyzed_program.type_by_node_id.get(binary_expression.left.id).?;
                const result_register = self.emitLoweredBinaryOperation(
                    typed_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
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
                const operation_type = typed_program.analyzed_program.type_by_node_id.get(node.id).?;
                const instruction_type = typed_program.llvmIrType(operation_type);
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
                const symbol_id = typed_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const value_type_id = typed_program.analyzed_program.type_by_node_id.get(value_declaration.value.id).?;
                const llvm_ir_type = typed_program.llvmIrType(value_type_id);

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

                const value_type_id = typed_program.analyzed_program.type_by_node_id.get(assignment.target.id).?;
                const llvm_ir_type = typed_program.llvmIrType(value_type_id);
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

                        const result_register = self.emitLoweredBinaryOperation(
                            lowering.BinaryOperationLowerer.decisionFor(
                                binary_operator,
                                value_type_id,
                                typed_program.analyzed_program,
                            ),
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
                        typed_program.analyzed_program.type_by_node_id.get(subject.id).? == typed_program.analyzed_program.type_store.boolean_type_id
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

    fn emitCallExpression(
        self: *@This(),
        node: *const ast.Node,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const call_dispatch = typed_program.call_dispatch_decision_by_node_id.get(node.id) orelse unreachable;

        return switch (call_dispatch) {
            .UserFunction => |user_function| self.emitUserFunctionCall(
                user_function,
                call_expression,
                entry_label,
                typed_program,
                environment,
            ),
            .Builtin => |builtin_call_kind| self.emitBuiltinCall(
                builtin_call_kind,
                call_expression,
                entry_label,
                typed_program,
                environment,
            ),
            .ArrayMethod => |array_method| {
                const callee_member_access = switch (call_expression.callee.kind) {
                    .MemberAccess => |member_access| member_access,
                    else => unreachable,
                };
                return switch (array_method) {
                    .Append => self.emitArrayAppendCall(
                        &callee_member_access,
                        call_expression,
                        entry_label,
                        typed_program,
                        environment,
                    ),
                };
            },
            .StringMethod => |string_method| {
                const callee_member_access = switch (call_expression.callee.kind) {
                    .MemberAccess => |member_access| member_access,
                    else => unreachable,
                };
                return self.emitStringMethodCall(
                    string_method,
                    &callee_member_access,
                    call_expression,
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .IntegerMethod => |integer_method| {
                const callee_member_access = switch (call_expression.callee.kind) {
                    .MemberAccess => |member_access| member_access,
                    else => unreachable,
                };
                return self.emitIntegerMethodCall(
                    integer_method,
                    &callee_member_access,
                    call_expression,
                    entry_label,
                    typed_program,
                    environment,
                );
            },
        };
    }

    fn emitUserFunctionCall(
        self: *@This(),
        user_function: anytype,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        var current_label = entry_label;
        var argument_registers = std.ArrayList(Register){};
        defer argument_registers.deinit(self.allocator);

        if (user_function.receiver_node_id) |receiver_node_id| {
            const callee_member_access = switch (call_expression.callee.kind) {
                .MemberAccess => |member_access| member_access,
                else => unreachable,
            };
            if (callee_member_access.base.id != receiver_node_id) unreachable;

            const receiver_result = self.emitNode(
                callee_member_access.base,
                current_label,
                typed_program,
                environment,
            );
            if (receiver_result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                return .{ .exit_label = null, .register = null };
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
                return .{ .exit_label = null, .register = null };
            }
            argument_registers.append(
                self.allocator,
                argument_result.register orelse unreachable,
            ) catch unreachable;
        }

        return self.emitDirectFunctionCall(
            user_function.function_symbol_id,
            user_function.owning_structure_symbol_id,
            argument_registers.items,
            current_label,
            typed_program,
        );
    }

    fn emitBuiltinCall(
        self: *@This(),
        builtin_call_kind: lowering.lowering_types.BuiltinCallKind,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return switch (builtin_call_kind) {
            .PrintInt => {
                if (call_expression.arguments.len != 1) unreachable;
                const argument_result = self.emitNode(
                    &call_expression.arguments[0],
                    entry_label,
                    typed_program,
                    environment,
                );
                if (argument_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }

                self.runtime_call_emitter.emitPrintIntCall(
                    self.function_ir_builder,
                    argument_result.register orelse unreachable,
                );
                return .{
                    .exit_label = argument_result.exit_label,
                    .register = null,
                };
            },
            .PrintString => {
                if (call_expression.arguments.len != 1) unreachable;
                const argument_result = self.emitNode(
                    &call_expression.arguments[0],
                    entry_label,
                    typed_program,
                    environment,
                );
                if (argument_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }

                self.runtime_call_emitter.emitPrintStringCall(
                    self.function_ir_builder,
                    self.emitStringParts(argument_result.register orelse unreachable),
                );
                return .{
                    .exit_label = argument_result.exit_label,
                    .register = null,
                };
            },
            .ReadFile => {
                if (call_expression.arguments.len != 1) unreachable;
                const path_result = self.emitNode(
                    &call_expression.arguments[0],
                    entry_label,
                    typed_program,
                    environment,
                );
                if (path_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }

                const result_register = self.runtime_call_emitter.emitReadFileCall(
                    self.function_ir_builder,
                    self.function_symbol_generator,
                    self.emitStringParts(path_result.register orelse unreachable),
                );
                return .{
                    .exit_label = path_result.exit_label,
                    .register = result_register,
                };
            },
            .ReadLine => {
                if (call_expression.arguments.len != 0) unreachable;
                return .{
                    .exit_label = entry_label,
                    .register = self.runtime_call_emitter.emitReadLineCall(
                        self.function_ir_builder,
                        self.function_symbol_generator,
                    ),
                };
            },
            .GetArguments => {
                if (call_expression.arguments.len != 0) unreachable;
                return .{
                    .exit_label = entry_label,
                    .register = self.runtime_call_emitter.emitGetArgumentsCall(
                        self.function_ir_builder,
                        self.function_symbol_generator,
                    ),
                };
            },
        };
    }

    fn emitDirectFunctionCall(
        self: *@This(),
        callee_symbol_id: symbols.SymbolId,
        owning_structure_symbol_id: ?symbols.SymbolId,
        argument_registers: []const Register,
        current_label: Label,
        typed_program: *const lowering.LoweredProgram,
    ) EmissionResult {
        const callee_symbol = typed_program.analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
        const resolved_function = typed_program.analyzed_program.resolved_program.resolved_function_by_symbol_id.get(callee_symbol_id) orelse unreachable;

        var argument_list_buffer = std.ArrayList(u8){};
        defer argument_list_buffer.deinit(self.allocator);
        for (resolved_function.parameters, argument_registers, 0..) |parameter, argument_register, index| {
            const parameter_type_id = typed_program.analyzed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
            if (index > 0) {
                argument_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            argument_list_buffer.writer(self.allocator).print(
                "{s} {s}",
                .{
                    typed_program.llvmIrType(parameter_type_id),
                    argument_register,
                },
            ) catch unreachable;
        }

        const function_name = if (owning_structure_symbol_id) |structure_symbol_id|
            self.symbol_generator.generateStructureFunctionName(
                typed_program.analyzed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id),
                callee_symbol,
            )
        else
            self.symbol_generator.generateFunctionName(callee_symbol);
        const function_type_id = typed_program.analyzed_program.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
        const function_return_type_id = switch (typed_program.analyzed_program.type_store.getType(function_type_id)) {
            .Function => |id| typed_program.analyzed_program.type_store.function_types.items[id].return_type,
            else => unreachable,
        };
        const function_return_llvm_ir_type = typed_program.llvmIrType(function_return_type_id);
        if (function_return_type_id == typed_program.analyzed_program.type_store.unit_type_id) {
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
    }

    fn emitLoweredBinaryOperation(
        self: *@This(),
        decision: lowering.lowering_types.BinaryOperationDecision,
        operand_type_id: typing.TypeId,
        left_register: Register,
        right_register: Register,
        typed_program: *const lowering.LoweredProgram,
    ) Register {
        return switch (decision) {
            .PrimitiveOperation => |primitive_operation| {
                const llvm_ir_type = typed_program.llvmIrType(operand_type_id);
                const operator_instruction = switch (primitive_operation) {
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
            },
            .StringConcatenate => self.runtime_call_emitter.emitStringConcatenateCall(
                self.function_ir_builder,
                self.function_symbol_generator,
                self.emitStringParts(left_register),
                self.emitStringParts(right_register),
            ),
            .StringCompareEqual => self.runtime_call_emitter.emitStringCompareCall(
                self.function_ir_builder,
                self.function_symbol_generator,
                self.emitStringParts(left_register),
                self.emitStringParts(right_register),
            ),
            .StringCompareNotEqual => compare_not_equal: {
                const equal_register = self.runtime_call_emitter.emitStringCompareCall(
                    self.function_ir_builder,
                    self.function_symbol_generator,
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
        };
    }

    fn emitMemberAccess(
        self: *@This(),
        node: *const ast.Node,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const member_access_decision = typed_program.member_access_decision_by_node_id.get(node.id) orelse unreachable;
        switch (member_access_decision) {
            .ArrayLength => {
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
            .StringLength => {
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
            .StructureField => |structure_field| {
                const member_pointer_result = self.emitStructureFieldPointer(
                    member_access,
                    structure_field.field_index,
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
                    typed_program.llvmIrType(typed_program.analyzed_program.type_by_node_id.get(node.id).?),
                );

                return .{
                    .exit_label = member_pointer_result.exit_label,
                    .register = member_register,
                };
            },
            .StructureMethod => unreachable,
            .StructureTypeFunction => unreachable,
            .ArrayMethod => unreachable,
            .StringMethod => unreachable,
            .IntegerMethod => unreachable,
        }
    }

    fn emitPlace(
        self: *@This(),
        target: *const ast.Node,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const place_decision = typed_program.place_decision_by_node_id.get(target.id) orelse unreachable;
        return switch (place_decision) {
            .IdentifierBinding => |identifier_binding| .{
                .exit_label = entry_label,
                .register = environment.storage_by_symbol_id.get(identifier_binding.symbol_id).?,
            },
            .StructureField => |structure_field| {
                const member_access = switch (target.kind) {
                    .MemberAccess => |resolved_member_access| resolved_member_access,
                    else => unreachable,
                };
                return self.emitStructureFieldPointer(
                    &member_access,
                    structure_field.field_index,
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .ArrayElement => {
                const index_access = switch (target.kind) {
                    .IndexAccess => |resolved_index_access| resolved_index_access,
                    else => unreachable,
                };
                return self.emitIndexAccessPointer(
                    &index_access,
                    entry_label,
                    typed_program,
                    environment,
                );
            },
        };
    }

    fn emitStructureFieldPointer(
        self: *@This(),
        member_access: *const ast.MemberAccess,
        field_index: u32,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
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

        const base_type_id = typed_program.analyzed_program.type_by_node_id.get(member_access.base.id) orelse unreachable;
        switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
            .Structure => {},
            else => unreachable,
        }
        const structure_symbol = typed_program.structureSymbolForTypeId(base_type_id);
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
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const node_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
        const structure_symbol = typed_program.structureSymbolForTypeId(node_type_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);
        const structure_type_id = switch (typed_program.analyzed_program.type_store.getType(node_type_id)) {
            .Structure => |id| id,
            else => unreachable,
        };
        const structure_type = typed_program.analyzed_program.type_store.structure_types.items[structure_type_id];
        const structure_construction_layout = typed_program.analyzed_program.structure_construction_layout_by_node_id.get(
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

            const field_llvm_ir_type = typed_program.llvmIrType(structure_field.type_id);
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
        typed_program: *const lowering.LoweredProgram,
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

        const iterable_type_id = typed_program.analyzed_program.type_by_node_id.get(for_in.iterable.id) orelse unreachable;
        const element_type_id = switch (typed_program.analyzed_program.type_store.getType(iterable_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = typed_program.llvmIrType(element_type_id);

        const item_symbol_id = typed_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
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
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const array_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id) orelse unreachable;
        const element_type_id = switch (typed_program.analyzed_program.type_store.getType(array_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = typed_program.llvmIrType(element_type_id);
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
        typed_program: *const lowering.LoweredProgram,
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

        const base_type_id = typed_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = typed_program.llvmIrType(element_type_id);

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
        typed_program: *const lowering.LoweredProgram,
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

        const base_type_id = typed_program.analyzed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.analyzed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = typed_program.llvmIrType(element_type_id);

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
        const line = index_access.left_bracket.line;
        const column = index_access.left_bracket.column;
        self.runtime_call_emitter.emitPanicIndexOutOfBoundsCall(
            self.function_ir_builder,
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
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        if (call_expression.arguments.len != 1) unreachable;

        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const argument_result = self.emitNode(&call_expression.arguments[0], base_result.exit_label.?, typed_program, environment);
        if (argument_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const array_type_id = typed_program.analyzed_program.type_by_node_id.get(callee_member_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.analyzed_program.type_store.getType(array_type_id)) {
            .Array => |element_type_id| element_type_id,
            else => unreachable,
        };
        const element_llvm_type = typed_program.llvmIrType(element_type_id);

        // The runtime helper grows the backing storage if needed and returns the slot for the new element.
        const slot_register = self.runtime_call_emitter.emitArrayAppendSlotCall(
            self.function_ir_builder,
            self.function_symbol_generator,
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
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        return switch (string_method) {
            .Trim => {
                if (call_expression.arguments.len != 0) unreachable;
                const result_register = self.runtime_call_emitter.emitStringTrimCall(
                    self.function_ir_builder,
                    self.function_symbol_generator,
                    self.emitStringParts(base_result.register orelse unreachable),
                );
                return .{
                    .exit_label = base_result.exit_label,
                    .register = result_register,
                };
            },
            .Split => {
                if (call_expression.arguments.len != 1) unreachable;

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
                    self.function_ir_builder,
                    self.function_symbol_generator,
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

                const result_register = self.runtime_call_emitter.emitStringToIntCall(
                    self.function_ir_builder,
                    self.function_symbol_generator,
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
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(callee_member_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        return switch (integer_method) {
            .ToString => {
                if (call_expression.arguments.len != 0) unreachable;

                const result_register = self.runtime_call_emitter.emitIntToStringCall(
                    self.function_ir_builder,
                    self.function_symbol_generator,
                    base_result.register orelse unreachable,
                );
                return .{
                    .exit_label = base_result.exit_label,
                    .register = result_register,
                };
            },
        };
    }
    fn emitDecisionConstruct(
        self: *@This(),
        node: *const ast.Node,
        decision_construct: DecisionConstruct,
        label_names: DecisionLabelNames,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
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
            subject_type_id = typed_program.analyzed_program.type_by_node_id.get(subject.id).?;
        }

        const result_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id).?;
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
                if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
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

                    const comparison_register = self.emitLoweredBinaryOperation(
                        lowering.BinaryOperationLowerer.decisionFor(
                            .Equal,
                            subject_type_id.?,
                            typed_program.analyzed_program,
                        ),
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
                    if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
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
                    if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
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
        if (result_type_id == typed_program.analyzed_program.type_store.unit_type_id) {
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
                typed_program.llvmIrType(result_type_id),
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
        typed_program: *const lowering.LoweredProgram,
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
        typed_program: *const lowering.LoweredProgram,
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
