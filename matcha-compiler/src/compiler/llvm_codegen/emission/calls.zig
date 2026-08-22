const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");

const Register = function_symbol_generator_module.Register;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitCallExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const call_dispatch = lowered_program.call_dispatch_decision_by_node_id.get(node.id) orelse unreachable;

    return switch (call_dispatch) {
        .UserFunction => |user_function| emitUserFunctionCall(
            emitter,
            user_function,
            call_expression,
            lowered_program,
            environment,
        ),
        .Builtin => |builtin_call_kind| emitBuiltinCall(
            emitter,
            builtin_call_kind,
            call_expression,
            lowered_program,
            environment,
        ),
        .ArrayMethod => |array_method| {
            const callee_member_access = switch (call_expression.callee.kind) {
                .MemberAccess => |member_access| member_access,
                else => unreachable,
            };
            return switch (array_method) {
                .Append => emitArrayAppendCall(
                    emitter,
                    &callee_member_access,
                    call_expression,
                    lowered_program,
                    environment,
                ),
            };
        },
        .StringMethod => |string_method| {
            const callee_member_access = switch (call_expression.callee.kind) {
                .MemberAccess => |member_access| member_access,
                else => unreachable,
            };
            return emitStringMethodCall(
                emitter,
                string_method,
                &callee_member_access,
                call_expression,
                lowered_program,
                environment,
            );
        },
        .IntegerMethod => |integer_method| {
            const callee_member_access = switch (call_expression.callee.kind) {
                .MemberAccess => |member_access| member_access,
                else => unreachable,
            };
            return emitIntegerMethodCall(
                emitter,
                integer_method,
                &callee_member_access,
                call_expression,
                lowered_program,
                environment,
            );
        },
    };
}

fn emitUserFunctionCall(
    emitter: *NodeEmitter,
    user_function: anytype,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    var argument_registers = std.ArrayList(Register){};
    defer argument_registers.deinit(emitter.allocator);

    if (user_function.receiver_node_id) |receiver_node_id| {
        const callee_member_access = switch (call_expression.callee.kind) {
            .MemberAccess => |member_access| member_access,
            else => unreachable,
        };
        if (callee_member_access.base.id != receiver_node_id) unreachable;

        const receiver_emission_result = emitter.emitNode(callee_member_access.base, lowered_program, environment);
        switch (receiver_emission_result) {
            .register => |receiver_register| argument_registers.append(
                emitter.allocator,
                receiver_register,
            ) catch unreachable,
            else => {},
        }
    }

    for (call_expression.arguments) |*argument| {
        const argument_emission_result = emitter.emitNode(argument, lowered_program, environment);
        const argument_register = switch (argument_emission_result) {
            .register => |register| register,
            else => continue,
        };
        argument_registers.append(
            emitter.allocator,
            argument_register,
        ) catch unreachable;
    }

    return emitDirectFunctionCall(
        emitter,
        user_function.function_symbol_id,
        user_function.owning_structure_symbol_id,
        argument_registers.items,
        lowered_program,
    );
}

fn emitBuiltinCall(
    emitter: *NodeEmitter,
    builtin_call_kind: lowering.lowering_types.BuiltinCallKind,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    switch (builtin_call_kind) {
        .PrintInt => {
            if (call_expression.arguments.len != 1) unreachable;
            const argument_register = emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            emitter.runtime_call_emitter.emitPrintIntCall(
                emitter.function_ir_builder,
                argument_register.expectRegister(),
            );
            return .zero_sized;
        },
        .PrintString => {
            if (call_expression.arguments.len != 1) unreachable;
            const argument_register = emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            emitter.runtime_call_emitter.emitPrintStringCall(
                emitter.function_ir_builder,
                emitter.emitStringParts(argument_register.expectRegister()),
            );
            return .zero_sized;
        },
        .ReadFile => {
            if (call_expression.arguments.len != 1) unreachable;
            const path_register = emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            return .{ .register = emitter.runtime_call_emitter.emitReadFileCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(path_register.expectRegister()),
            ) };
        },
        .ReadLine => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .register = emitter.runtime_call_emitter.emitReadLineCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
            ) };
        },
        .GetArguments => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .register = emitter.runtime_call_emitter.emitGetArgumentsCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
            ) };
        },
    }
}

fn emitDirectFunctionCall(
    emitter: *NodeEmitter,
    callee_symbol_id: symbols.SymbolId,
    owning_structure_symbol_id: ?symbols.SymbolId,
    argument_registers: []const Register,
    lowered_program: *const lowering.LoweredProgram,
) EmissionResult {
    const callee_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
    const resolved_function = lowered_program.analyzed_program.resolved_program.resolved_function_by_symbol_id.get(callee_symbol_id) orelse unreachable;
    const function_layout = lowered_program.function_layout_by_symbol_id.get(callee_symbol_id) orelse unreachable;

    var argument_list_buffer = std.ArrayList(u8){};
    defer argument_list_buffer.deinit(emitter.allocator);

    for (function_layout.parameter_index_by_definition_index, 0..) |parameter_layout_index_kind, parameter_definition_index| {
        const parameter_layout_index = switch (parameter_layout_index_kind) {
            .Absent => continue,
            .Index => |index| index,
        };
        if (parameter_layout_index > 0) {
            argument_list_buffer.writer(emitter.allocator).print(", ", .{}) catch unreachable;
        }
        const parameter = resolved_function.parameters[parameter_definition_index];
        const parameter_type_id = lowered_program.analyzed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
        const parameter_llvm_type = lowered_program.getLlvmIrType(parameter_type_id);
        const argument_register = argument_registers[parameter_layout_index];

        argument_list_buffer.writer(emitter.allocator).print(
            "{s} {s}",
            .{ parameter_llvm_type, argument_register },
        ) catch unreachable;
    }

    const function_name = if (owning_structure_symbol_id) |structure_symbol_id|
        emitter.symbol_generator.generateStructureFunctionName(
            lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id),
            callee_symbol,
        )
    else
        emitter.symbol_generator.generateFunctionName(callee_symbol);
    const function_type_id = lowered_program.analyzed_program.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
    const function_return_type_id = switch (lowered_program.analyzed_program.type_store.getType(function_type_id)) {
        .Function => |id| lowered_program.analyzed_program.type_store.function_types.items[id].return_type,
        else => unreachable,
    };
    const function_return_llvm_ir_type = lowered_program.getLlvmIrType(function_return_type_id);

    switch (function_layout.runtime_return_kind) {
        .Absent => {
            const call_instruction = std.fmt.allocPrint(
                emitter.allocator,
                "call void @{s}({s})",
                .{ function_name, argument_list_buffer.items },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(call_instruction);

            return .zero_sized;
        },
        .Present => {
            const result_register = emitter.function_symbol_generator.generateRegister();
            const call_instruction = std.fmt.allocPrint(
                emitter.allocator,
                "{s} = call {s} @{s}({s})",
                .{ result_register, function_return_llvm_ir_type, function_name, argument_list_buffer.items },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(call_instruction);

            return .{ .register = result_register };
        },
    }
}

fn emitArrayAppendCall(
    emitter: *NodeEmitter,
    callee_member_access: *const ast.MemberAccess,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    if (call_expression.arguments.len != 1) unreachable;

    const base_register = emitter.emitNode(callee_member_access.base, lowered_program, environment).expectRegister();
    const argument_register = emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);

    const array_type_id = lowered_program.analyzed_program.type_by_node_id.get(callee_member_access.base.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(array_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };

    const element_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(element_type_id) orelse unreachable;
    if (!element_runtime_representation.hasRuntimeRepresentation()) {
        // In case the element type has no runtime representation we just increment the length of the array and return,
        // since the element doesn't need to be stored anywhere.

        // load length of the array
        const length_pointer_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
            .{ length_pointer_register, base_register },
        ) catch unreachable);
        const length_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

        // increment length of the array
        const new_length_register = emitter.function_symbol_generator.generateRegister();
        emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = add i64 {s}, 1",
            .{ new_length_register, length_register },
        ) catch unreachable);

        // store new length of the array
        emitter.function_ir_builder.emitStore(new_length_register, length_pointer_register, "i64");

        return .zero_sized;
    }

    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);

    // The runtime helper grows the backing storage if needed and returns the slot for the new element.
    const slot_register = emitter.runtime_call_emitter.emitArrayAppendSlotCall(
        emitter.function_ir_builder,
        emitter.function_symbol_generator,
        base_register,
        element_llvm_type,
    );

    emitter.function_ir_builder.emitStore(argument_register.expectRegister(), slot_register, element_llvm_type);

    return .zero_sized;
}

fn emitStringMethodCall(
    emitter: *NodeEmitter,
    string_method: typing.StringInstanceMethod,
    callee_member_access: *const ast.MemberAccess,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const base_register = emitter.emitNode(callee_member_access.base, lowered_program, environment).expectRegister();

    switch (string_method) {
        .Trim => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .register = emitter.runtime_call_emitter.emitStringTrimCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(base_register),
            ) };
        },
        .Split => {
            if (call_expression.arguments.len != 1) unreachable;

            const delimiter_register = emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            return .{ .register = emitter.runtime_call_emitter.emitStringSplitCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(base_register),
                emitter.emitStringParts(delimiter_register.expectRegister()),
            ) };
        },
        .ToInt => {
            if (call_expression.arguments.len != 0) unreachable;

            return .{ .register = emitter.runtime_call_emitter.emitStringToIntCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(base_register),
            ) };
        },
    }
}

fn emitIntegerMethodCall(
    emitter: *NodeEmitter,
    integer_method: typing.IntegerInstanceMethod,
    callee_member_access: *const ast.MemberAccess,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const base_register = emitter.emitNode(callee_member_access.base, lowered_program, environment);

    switch (integer_method) {
        .ToString => {
            if (call_expression.arguments.len != 0) unreachable;

            return .{ .register = emitter.runtime_call_emitter.emitIntToStringCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                base_register.expectRegister(),
            ) };
        },
    }
}
