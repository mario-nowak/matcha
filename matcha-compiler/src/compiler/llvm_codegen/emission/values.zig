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
    const symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
    const storage = environment.storage_by_symbol_id.get(symbol_id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(
        lowered_program.analyzed_program.type_by_node_id.get(node.id).?,
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
    const left_register = emitter.emitNode(binary_expression.left, lowered_program, environment);
    const right_register = emitter.emitNode(binary_expression.right, lowered_program, environment);
    const left_operand_type = lowered_program.analyzed_program.type_by_node_id.get(binary_expression.left.id).?;

    return .{ .register = emitLoweredBinaryOperation(
        emitter,
        lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
        left_operand_type,
        left_register.expectRegister(),
        right_register.expectRegister(),
        lowered_program,
    ) };
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
    const operation_type = lowered_program.analyzed_program.type_by_node_id.get(node.id).?;
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
                .And => "and",
                .Or => "or",
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
    };
}
