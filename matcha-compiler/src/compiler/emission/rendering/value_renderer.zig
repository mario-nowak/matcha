const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");
const function_emission = @import("function_emission");
const support = @import("node_rendering_support.zig");

const Register = function_emission.Register;
const Label = function_emission.Label;
const Environment = support.Environment;
const EmissionResult = support.EmissionResult;

pub fn emitCallExpression(
    self: anytype,
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

pub fn emitUserFunctionCall(
    self: anytype,
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

pub fn emitBuiltinCall(
    self: anytype,
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

pub fn emitDirectFunctionCall(
    self: anytype,
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

pub fn emitLoweredBinaryOperation(
    self: anytype,
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

pub fn emitArrayAppendCall(
    self: anytype,
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

pub fn emitStringMethodCall(
    self: anytype,
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

pub fn emitIntegerMethodCall(
    self: anytype,
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
