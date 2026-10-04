const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const emitUnionConstruction = @import("aggregates.zig").emitUnionConstruction;

const Value = function_symbol_generator_module.Value;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitCallExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const call_dispatch = lowered_program.call_dispatch_decision_by_node_id.get(node.id) orelse unreachable;

    return switch (call_dispatch) {
        .UserFunction => |user_function| try emitUserFunctionCall(
            emitter,
            user_function,
            call_expression,
            lowered_program,
            environment,
        ),
        .UnionConstruction => |union_construction| try emitUnionConstruction(
            emitter,
            union_construction.union_type_id,
            union_construction.case_index,
            &call_expression.arguments[0],
            lowered_program,
            environment,
        ),
        .Builtin => |builtin_call_kind| try emitBuiltinCall(
            emitter,
            builtin_call_kind,
            call_expression,
            lowered_program,
            environment,
        ),
        .ArrayMethod => |array_method| {
            const callee_member_expression = switch (call_expression.callee.kind) {
                .MemberExpression => |member_expression| member_expression,
                else => unreachable,
            };
            return switch (array_method) {
                .Append => try emitArrayAppendCall(
                    emitter,
                    &callee_member_expression,
                    call_expression,
                    lowered_program,
                    environment,
                ),
            };
        },
        .StringMethod => |string_method| {
            const callee_member_expression = switch (call_expression.callee.kind) {
                .MemberExpression => |member_expression| member_expression,
                else => unreachable,
            };
            return emitStringMethodCall(
                emitter,
                string_method,
                &callee_member_expression,
                call_expression,
                lowered_program,
                environment,
            );
        },
        .IntegerMethod => |integer_method| {
            const callee_member_expression = switch (call_expression.callee.kind) {
                .MemberExpression => |member_expression| member_expression,
                else => unreachable,
            };
            return emitIntegerMethodCall(
                emitter,
                integer_method,
                &callee_member_expression,
                call_expression,
                lowered_program,
                environment,
            );
        },
    };
}

fn emitUserFunctionCall(
    emitter: *NodeEmitter,
    user_function: lowering.lowering_types.UserFunctionCall,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    var argument_values = std.ArrayList(Value){};

    if (user_function.receiver_node_id) |receiver_node_id| {
        const callee_member_expression = switch (call_expression.callee.kind) {
            .MemberExpression => |member_expression| member_expression,
            else => unreachable,
        };
        if (callee_member_expression.base.id != receiver_node_id) unreachable;

        const receiver_emission_result = try emitter.emitNode(callee_member_expression.base, lowered_program, environment);
        switch (receiver_emission_result) {
            .value => |receiver_value| try argument_values.append(
                emitter.arena,
                receiver_value,
            ),
            else => {},
        }
    }

    for (call_expression.arguments) |*argument| {
        const argument_emission_result = try emitter.emitNode(argument, lowered_program, environment);
        const argument_value = switch (argument_emission_result) {
            .value => |value| value,
            else => continue,
        };
        try argument_values.append(
            emitter.arena,
            argument_value,
        );
    }

    return emitDirectFunctionCall(
        emitter,
        user_function.function_symbol_id,
        argument_values.items,
        lowered_program,
    );
}

fn emitBuiltinCall(
    emitter: *NodeEmitter,
    builtin_call_kind: lowering.lowering_types.BuiltinCallKind,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    switch (builtin_call_kind) {
        .PrintInt => {
            if (call_expression.arguments.len != 1) unreachable;
            const argument_value = try emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            try emitter.runtime_call_emitter.emitPrintIntCall(
                emitter.function_ir_builder,
                argument_value.expectValue(),
            );
            return .zero_sized;
        },
        .PrintString => {
            if (call_expression.arguments.len != 1) unreachable;
            const argument_value = try emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            try emitter.runtime_call_emitter.emitPrintStringCall(
                emitter.function_ir_builder,
                try emitter.emitStringParts(argument_value.expectValue()),
            );
            return .zero_sized;
        },
        .ReadFile => {
            if (call_expression.arguments.len != 1) unreachable;
            const path_value = try emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            return .{ .value = try emitter.runtime_call_emitter.emitReadFileCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                try emitter.emitStringParts(path_value.expectValue()),
            ) };
        },
        .ReadLine => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .value = try emitter.runtime_call_emitter.emitReadLineCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
            ) };
        },
        .GetArguments => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .value = try emitter.runtime_call_emitter.emitGetArgumentsCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
            ) };
        },
    }
}

fn emitDirectFunctionCall(
    emitter: *NodeEmitter,
    callee_symbol_id: symbols.SymbolId,
    argument_values: []const Value,
    lowered_program: *const lowering.LoweredProgram,
) !EmissionResult {
    const callee_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
    const function_symbol_information = switch (callee_symbol.kind) {
        .Function => |function_symbol_information| function_symbol_information,
        else => unreachable,
    };
    const function_layout = lowered_program.function_layout_by_symbol_id.get(callee_symbol_id) orelse unreachable;

    var argument_list_buffer = std.ArrayList(u8){};

    for (function_layout.parameter_index_kind_by_definition_index, 0..) |parameter_layout_index_kind, parameter_definition_index| {
        const parameter_layout_index = switch (parameter_layout_index_kind) {
            .Absent => continue,
            .Index => |index| index,
        };
        if (parameter_layout_index > 0) {
            try argument_list_buffer.writer(emitter.arena).print(", ", .{});
        }
        const parameter_symbol_id = function_symbol_information.parameter_symbol_ids[parameter_definition_index];
        const parameter_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
        const parameter_llvm_type = lowered_program.getLlvmIrType(parameter_type_id);
        const argument_value = argument_values[parameter_layout_index];

        try argument_list_buffer.writer(emitter.arena).print(
            "{s} {s}",
            .{ parameter_llvm_type, argument_value },
        );
    }

    const function_name = function_layout.llvm_function_name;
    const function_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(callee_symbol_id) orelse unreachable;
    const function_return_type_id = switch (lowered_program.analyzed_program.type_store.getType(function_type_id)) {
        .Function => |function_type| function_type.return_type_id,
        else => unreachable,
    };
    const function_return_llvm_ir_type = lowered_program.getLlvmIrType(function_return_type_id);

    switch (function_layout.return_type_value_kind) {
        .Absent => {
            const call_instruction = try std.fmt.allocPrint(
                emitter.arena,
                "call void @{s}({s})",
                .{ function_name, argument_list_buffer.items },
            );
            try emitter.function_ir_builder.emitInstruction(call_instruction);

            return .zero_sized;
        },
        .Present => {
            const result_value = try emitter.function_symbol_generator.generateValueName();
            const call_instruction = try std.fmt.allocPrint(
                emitter.arena,
                "{s} = call {s} @{s}({s})",
                .{ result_value, function_return_llvm_ir_type, function_name, argument_list_buffer.items },
            );
            try emitter.function_ir_builder.emitInstruction(call_instruction);

            return .{ .value = result_value };
        },
    }
}

fn emitArrayAppendCall(
    emitter: *NodeEmitter,
    callee_member_expression: *const ast.MemberExpression,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    if (call_expression.arguments.len != 1) unreachable;

    const base_value = (try emitter.emitNode(callee_member_expression.base, lowered_program, environment)).expectValue();
    const argument_value = try emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);

    const array_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(callee_member_expression.base.id) orelse unreachable;
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
        const length_pointer_value = try emitter.function_symbol_generator.generateValueName();
        try emitter.function_ir_builder.emitFieldPointer(
            length_pointer_value,
            lowering.llvm_type.array_llvm_type_name,
            base_value,
            lowering.llvm_type.array_length_field_index,
        );
        const length_value = try emitter.function_symbol_generator.generateValueName();
        try emitter.function_ir_builder.emitLoad(length_value, length_pointer_value, "i64");

        // increment length of the array
        const new_length_value = try emitter.function_symbol_generator.generateValueName();
        try emitter.function_ir_builder.emitInstruction(try std.fmt.allocPrint(
            emitter.arena,
            "{s} = add i64 {s}, 1",
            .{ new_length_value, length_value },
        ));

        // store new length of the array
        try emitter.function_ir_builder.emitStore(new_length_value, length_pointer_value, "i64");

        return .zero_sized;
    }

    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);

    // The runtime helper grows the backing storage if needed and returns the slot for the new element.
    const slot_value = try emitter.runtime_call_emitter.emitArrayAppendSlotCall(
        emitter.function_ir_builder,
        emitter.function_symbol_generator,
        base_value,
        element_llvm_type,
    );

    try emitter.function_ir_builder.emitStore(argument_value.expectValue(), slot_value, element_llvm_type);

    return .zero_sized;
}

fn emitStringMethodCall(
    emitter: *NodeEmitter,
    string_method: typing.StringInstanceMethod,
    callee_member_expression: *const ast.MemberExpression,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const base_value = (try emitter.emitNode(callee_member_expression.base, lowered_program, environment)).expectValue();

    switch (string_method) {
        .Trim => {
            if (call_expression.arguments.len != 0) unreachable;
            return .{ .value = try emitter.runtime_call_emitter.emitStringTrimCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                try emitter.emitStringParts(base_value),
            ) };
        },
        .Split => {
            if (call_expression.arguments.len != 1) unreachable;

            const delimiter_value = try emitter.emitNode(&call_expression.arguments[0], lowered_program, environment);
            return .{ .value = try emitter.runtime_call_emitter.emitStringSplitCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                try emitter.emitStringParts(base_value),
                try emitter.emitStringParts(delimiter_value.expectValue()),
            ) };
        },
        .ToInt => {
            if (call_expression.arguments.len != 0) unreachable;

            return .{ .value = try emitter.runtime_call_emitter.emitStringToIntCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                try emitter.emitStringParts(base_value),
            ) };
        },
    }
}

fn emitIntegerMethodCall(
    emitter: *NodeEmitter,
    integer_method: typing.IntegerInstanceMethod,
    callee_member_expression: *const ast.MemberExpression,
    call_expression: *const ast.CallExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const base_value = try emitter.emitNode(callee_member_expression.base, lowered_program, environment);

    switch (integer_method) {
        .ToString => {
            if (call_expression.arguments.len != 0) unreachable;

            return .{ .value = try emitter.runtime_call_emitter.emitIntToStringCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                base_value.expectValue(),
            ) };
        },
    }
}
