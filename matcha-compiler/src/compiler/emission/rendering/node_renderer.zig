const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const function_emission = @import("function_emission");
const runtime = @import("runtime/module.zig");
const symbol_generator_module = @import("symbol_generator.zig");
const string_literal_renderer_module = @import("string_literal_renderer.zig");
const support = @import("node_rendering_support.zig");
const value_renderer = @import("value_renderer.zig");
const construction_renderer = @import("construction_renderer.zig");
const control_flow_renderer = @import("control_flow_renderer.zig");

const Register = function_emission.Register;
const Label = function_emission.Label;
const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;
const RuntimeCallEmitter = runtime.RuntimeCallEmitter;
const RuntimeStringParts = runtime.RuntimeStringParts;
const SymbolGenerator = symbol_generator_module.SymbolGenerator;
const StringLiteralRenderer = string_literal_renderer_module.StringLiteralRenderer;

pub const Environment = support.Environment;
pub const EmissionResult = support.EmissionResult;

const LoopConstruct = control_flow_renderer.LoopConstruct;
const DecisionConstruct = control_flow_renderer.DecisionConstruct;
const DecisionArm = control_flow_renderer.DecisionArm;
const DecisionLabelNames = control_flow_renderer.DecisionLabelNames;

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
        return value_renderer.emitCallExpression(self, node, call_expression, entry_label, typed_program, environment);
    }

    fn emitUserFunctionCall(
        self: *@This(),
        user_function: anytype,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return value_renderer.emitUserFunctionCall(self, user_function, call_expression, entry_label, typed_program, environment);
    }

    fn emitBuiltinCall(
        self: *@This(),
        builtin_call_kind: lowering.lowering_types.BuiltinCallKind,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return value_renderer.emitBuiltinCall(self, builtin_call_kind, call_expression, entry_label, typed_program, environment);
    }

    fn emitDirectFunctionCall(
        self: *@This(),
        callee_symbol_id: symbols.SymbolId,
        owning_structure_symbol_id: ?symbols.SymbolId,
        argument_registers: []const Register,
        current_label: Label,
        typed_program: *const lowering.LoweredProgram,
    ) EmissionResult {
        return value_renderer.emitDirectFunctionCall(self, callee_symbol_id, owning_structure_symbol_id, argument_registers, current_label, typed_program);
    }

    fn emitLoweredBinaryOperation(
        self: *@This(),
        decision: lowering.lowering_types.BinaryOperationDecision,
        operand_type_id: typing.TypeId,
        left_register: Register,
        right_register: Register,
        typed_program: *const lowering.LoweredProgram,
    ) Register {
        return value_renderer.emitLoweredBinaryOperation(self, decision, operand_type_id, left_register, right_register, typed_program);
    }

    fn emitMemberAccess(
        self: *@This(),
        node: *const ast.Node,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitMemberAccess(self, node, member_access, entry_label, typed_program, environment);
    }

    fn emitPlace(
        self: *@This(),
        target: *const ast.Node,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitPlace(self, target, entry_label, typed_program, environment);
    }

    fn emitStructureFieldPointer(
        self: *@This(),
        member_access: *const ast.MemberAccess,
        field_index: u32,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitStructureFieldPointer(self, member_access, field_index, entry_label, typed_program, environment);
    }

    fn emitStructureConstruction(
        self: *@This(),
        node: *const ast.Node,
        fields: []const ast.StructureConstructionField,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitStructureConstruction(self, node, fields, entry_label, typed_program, environment);
    }

    fn emitForInArrayLoop(
        self: *@This(),
        node: *const ast.Node,
        for_in: *const ast.ForIn,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return control_flow_renderer.emitForInArrayLoop(self, node, for_in, entry_label, typed_program, environment);
    }

    fn emitArrayLiteral(
        self: *@This(),
        node: *const ast.Node,
        array_literal: *const ast.ArrayLiteral,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitArrayLiteral(self, node, array_literal, entry_label, typed_program, environment);
    }

    fn emitIndexAccess(
        self: *@This(),
        node: *const ast.Node,
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitIndexAccess(self, node, index_access, entry_label, typed_program, environment);
    }

    fn emitIndexAccessPointer(
        self: *@This(),
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return construction_renderer.emitIndexAccessPointer(self, index_access, entry_label, typed_program, environment);
    }

    fn emitArrayAppendCall(
        self: *@This(),
        callee_member_access: *const ast.MemberAccess,
        call_expression: *const ast.CallExpression,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return value_renderer.emitArrayAppendCall(self, callee_member_access, call_expression, entry_label, typed_program, environment);
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
        return value_renderer.emitStringMethodCall(self, string_method, callee_member_access, call_expression, entry_label, typed_program, environment);
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
        return value_renderer.emitIntegerMethodCall(self, integer_method, callee_member_access, call_expression, entry_label, typed_program, environment);
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
        return control_flow_renderer.emitDecisionConstruct(self, node, decision_construct, label_names, entry_label, typed_program, environment);
    }

    fn emitLoopConstruct(
        self: *@This(),
        loop_construct: LoopConstruct,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return control_flow_renderer.emitLoopConstruct(self, loop_construct, typed_program, environment);
    }

    fn emitBlock(
        self: *@This(),
        block: ast.Block,
        entry_label: Label,
        typed_program: *const lowering.LoweredProgram,
        environment: *Environment,
    ) EmissionResult {
        return control_flow_renderer.emitBlock(self, block, entry_label, typed_program, environment);
    }
};
