const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");

const Register = function_symbol_generator_module.Register;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;

pub fn emitIdentifier(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_node_id
        .get(node.id) orelse unreachable;
    if (!runtime_representation.hasRuntimeRepresentation()) {
        return .zero_sized;
    }

    const symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
    const storage = environment.storage_by_symbol_id.get(symbol_id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(
        lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?,
    );
    const register = emitter.function_symbol_generator.generateRegister();
    emitter.function_ir_builder.emitLoad(register, storage, llvm_ir_type);

    return .{ .register = register };
}

pub fn emitBinaryExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    binary_expression: *const ast.BinaryExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const decision = lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable;
    switch (decision) {
        .ShortCircuitAnd => return emitShortCircuitOperation(emitter, binary_expression, .And, lowered_program, environment),
        .ShortCircuitOr => return emitShortCircuitOperation(emitter, binary_expression, .Or, lowered_program, environment),
        else => {},
    }

    const left_register = emitter.emitNode(binary_expression.left, lowered_program, environment);
    const right_register = emitter.emitNode(binary_expression.right, lowered_program, environment);
    const left_operand_type = lowered_program.analyzed_program.type_id_by_node_id.get(binary_expression.left.id).?;

    // Unit operands have no runtime value. Their side effects already ran above, so the result is a constant.
    switch (decision) {
        .ZeroSizedCompareEqual => return .{ .register = "1" },
        .ZeroSizedCompareNotEqual => return .{ .register = "0" },
        else => {},
    }

    return .{ .register = emitLoweredBinaryOperation(
        emitter,
        decision,
        left_operand_type,
        left_register.expectRegister(),
        right_register.expectRegister(),
        lowered_program,
    ) };
}

// Emits the right operand only when the left operand does not decide the result already. The result is a phi of
// the deciding constant (false for `and`, true for `or`) and the value of the right operand.
fn emitShortCircuitOperation(
    emitter: *NodeEmitter,
    binary_expression: *const ast.BinaryExpression,
    operator: enum { And, Or },
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    const end_label_name, const right_label_name, const deciding_value = switch (operator) {
        .And => .{ "and_end", "and_right", "0" },
        .Or => .{ "or_end", "or_right", "1" },
    };
    const end_label = emitter.function_symbol_generator.generateLabel(end_label_name);
    const right_label = emitter.function_symbol_generator.generateLabel(right_label_name);

    const left_register = emitter.emitNode(binary_expression.left, lowered_program, environment).expectRegister();
    // The phi needs the block where the left operand ended, which is not the start block when the operand branches.
    const left_exit_label = builder.currentLabel() orelse unreachable;
    switch (operator) {
        .And => builder.emitBranchInstruction(left_register, &.{ right_label, end_label }),
        .Or => builder.emitBranchInstruction(left_register, &.{ end_label, right_label }),
    }

    builder.emitLabel(right_label);
    const right_register = emitter.emitNode(binary_expression.right, lowered_program, environment).expectRegister();
    const right_exit_label = builder.currentLabel() orelse unreachable;
    builder.emitBranchInstruction(null, &.{end_label});

    builder.emitLabel(end_label);
    const result_register = emitter.function_symbol_generator.generateRegister();
    const phi_instruction = std.fmt.allocPrint(
        emitter.allocator,
        "{s} = phi i1 [{s}, %{s}], [{s}, %{s}]",
        .{ result_register, deciding_value, left_exit_label, right_register, right_exit_label },
    ) catch unreachable;
    builder.emitInstruction(phi_instruction);

    return .{ .register = result_register };
}

pub fn emitUnaryExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    unary_expression: *const ast.UnaryExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const operand_register = emitter.emitNode(unary_expression.operand, lowered_program, environment).expectRegister();
    const result_register = emitter.function_symbol_generator.generateRegister();
    const operation_type = lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?;
    const instruction_type = lowered_program.getLlvmIrType(operation_type);
    const instruction = switch (unary_expression.operator) {
        .Negate => std.fmt.allocPrint(
            emitter.allocator,
            "{s} = sub {s} 0, {s}",
            .{ result_register, instruction_type, operand_register },
        ) catch unreachable,
        .Not => std.fmt.allocPrint(
            emitter.allocator,
            "{s} = xor {s} {s}, 1",
            .{ result_register, instruction_type, operand_register },
        ) catch unreachable,
    };
    emitter.function_ir_builder.emitInstruction(instruction);

    return .{ .register = result_register };
}

pub fn emitLoweredBinaryOperation(
    emitter: *NodeEmitter,
    decision: lowering.lowering_types.BinaryOperationDecision,
    operand_type_id: typing.TypeId,
    left_register: Register,
    right_register: Register,
    lowered_program: *const lowering.LoweredProgram,
) Register {
    return switch (decision) {
        .PrimitiveOperation => |primitive_operation| {
            const llvm_ir_type = lowered_program.getLlvmIrType(operand_type_id);
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
            };

            const result_register = emitter.function_symbol_generator.generateRegister();
            const instruction = std.fmt.allocPrint(
                emitter.allocator,
                "{s} = {s} {s} {s}, {s}",
                .{ result_register, operator_instruction, llvm_ir_type, left_register, right_register },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(instruction);

            return result_register;
        },
        .UnionCaseIndexComparison => {
            const union_case_index_type = lowering.lowering_types.union_case_index_llvm_type;
            const operator_instruction = "icmp eq";

            // The case index is the first field of every case, so it can be loaded from the union pointer directly
            const union_case_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitLoad(union_case_register, left_register, union_case_index_type);

            const result_register = emitter.function_symbol_generator.generateRegister();
            const instruction = std.fmt.allocPrint(
                emitter.allocator,
                "{s} = {s} {s} {s}, {s}",
                .{ result_register, operator_instruction, union_case_index_type, union_case_register, right_register },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(instruction);

            return result_register;
        },
        .StringConcatenate => emitter.runtime_call_emitter.emitStringConcatenateCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            emitter.emitStringParts(left_register),
            emitter.emitStringParts(right_register),
        ),
        .StringCompareEqual => emitter.runtime_call_emitter.emitStringCompareCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            emitter.emitStringParts(left_register),
            emitter.emitStringParts(right_register),
        ),
        .StringCompareNotEqual => compare_not_equal: {
            const equal_register = emitter.runtime_call_emitter.emitStringCompareCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(left_register),
                emitter.emitStringParts(right_register),
            );
            const result_register = emitter.function_symbol_generator.generateRegister();
            emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                emitter.allocator,
                "{s} = xor i1 {s}, 1",
                .{ result_register, equal_register },
            ) catch unreachable);
            break :compare_not_equal result_register;
        },
        .ZeroSizedCompareEqual, .ZeroSizedCompareNotEqual, .ShortCircuitAnd, .ShortCircuitOr => unreachable,
    };
}
