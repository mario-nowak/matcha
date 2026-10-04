const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");

const Value = function_symbol_generator_module.Value;
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
    const address = environment.address_by_symbol_id.get(symbol_id).?;
    const llvm_ir_type = lowered_program.getLlvmIrType(
        lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?,
    );
    const value = emitter.function_symbol_generator.generateValueName();
    emitter.function_ir_builder.emitLoad(value, address, llvm_ir_type);

    return .{ .value = value };
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

    const left_value = emitter.emitNode(binary_expression.left, lowered_program, environment);
    const right_value = emitter.emitNode(binary_expression.right, lowered_program, environment);
    const left_operand_type = lowered_program.analyzed_program.type_id_by_node_id.get(binary_expression.left.id).?;

    // Unit operands have no runtime value. Their side effects already ran above, so the result is a constant.
    switch (decision) {
        .ZeroSizedCompareEqual => return .{ .value = "1" },
        .ZeroSizedCompareNotEqual => return .{ .value = "0" },
        .CheckedDivide => return .{ .value = emitCheckedDivision(
            emitter,
            binary_expression.operator_token.line,
            binary_expression.operator_token.column,
            left_value.expectValue(),
            right_value.expectValue(),
        ) },
        else => {},
    }

    return .{ .value = emitLoweredBinaryOperation(
        emitter,
        decision,
        left_operand_type,
        left_value.expectValue(),
        right_value.expectValue(),
        lowered_program,
    ) };
}

// Panics on a zero divisor, because `sdiv` is undefined behavior for it. Also panics on `INT_MIN / -1`, whose quotient
// does not fit into an `int`.
fn emitCheckedDivision(
    emitter: *NodeEmitter,
    line: usize,
    column: usize,
    dividend_value: Value,
    divisor_value: Value,
) Value {
    const builder = emitter.function_ir_builder;
    const labels = emitter.function_symbol_generator.generateConstructLabels("division");
    const zero_divisor_label = labels.role("zero_divisor");
    const nonzero_divisor_label = labels.role("nonzero_divisor");
    const overflow_label = labels.role("overflow");
    const no_overflow_label = labels.role("no_overflow");

    const zero_divisor_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, 0", .{ zero_divisor_value, divisor_value }) catch unreachable);
    builder.emitBranchInstruction(zero_divisor_value, &.{ zero_divisor_label, nonzero_divisor_label });

    builder.emitLabel(zero_divisor_label);
    emitter.runtime_call_emitter.emitPanicDivisionByZeroCall(builder, line, column);
    builder.emitTerminatorInstruction("unreachable");

    builder.emitLabel(nonzero_divisor_label);
    const minimum_dividend_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, {d}", .{ minimum_dividend_value, dividend_value, std.math.minInt(i64) }) catch unreachable);
    const negative_one_divisor_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, -1", .{ negative_one_divisor_value, divisor_value }) catch unreachable);
    const overflow_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(emitter.arena, "{s} = and i1 {s}, {s}", .{ overflow_value, minimum_dividend_value, negative_one_divisor_value }) catch unreachable);
    builder.emitBranchInstruction(overflow_value, &.{ overflow_label, no_overflow_label });

    builder.emitLabel(overflow_label);
    emitter.runtime_call_emitter.emitPanicDivisionOverflowCall(builder, line, column);
    builder.emitTerminatorInstruction("unreachable");

    builder.emitLabel(no_overflow_label);
    const quotient_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(emitter.arena, "{s} = sdiv i64 {s}, {s}", .{ quotient_value, dividend_value, divisor_value }) catch unreachable);

    return quotient_value;
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
    const construct_name, const deciding_value = switch (operator) {
        .And => .{ "and", "0" },
        .Or => .{ "or", "1" },
    };
    const labels = emitter.function_symbol_generator.generateConstructLabels(construct_name);
    const end_label = labels.role("end");
    const right_label = labels.role("right");

    const left_value = emitter.emitNode(binary_expression.left, lowered_program, environment).expectValue();
    // The phi needs the block where the left operand ended, which is not the start block when the operand branches.
    const left_exit_label = builder.currentLabel() orelse unreachable;
    switch (operator) {
        .And => builder.emitBranchInstruction(left_value, &.{ right_label, end_label }),
        .Or => builder.emitBranchInstruction(left_value, &.{ end_label, right_label }),
    }

    builder.emitLabel(right_label);
    const right_value = emitter.emitNode(binary_expression.right, lowered_program, environment).expectValue();
    const right_exit_label = builder.currentLabel() orelse unreachable;
    builder.emitBranchInstruction(null, &.{end_label});

    builder.emitLabel(end_label);
    const result_value = emitter.function_symbol_generator.generateValueName();
    const phi_instruction = std.fmt.allocPrint(
        emitter.arena,
        "{s} = phi i1 [{s}, %{s}], [{s}, %{s}]",
        .{ result_value, deciding_value, left_exit_label, right_value, right_exit_label },
    ) catch unreachable;
    builder.emitInstruction(phi_instruction);

    return .{ .value = result_value };
}

pub fn emitUnaryExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    unary_expression: *const ast.UnaryExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const operand_value = emitter.emitNode(unary_expression.operand, lowered_program, environment).expectValue();
    const result_value = emitter.function_symbol_generator.generateValueName();
    const operation_type = lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?;
    const instruction_type = lowered_program.getLlvmIrType(operation_type);
    const instruction = switch (unary_expression.operator) {
        .Negate => std.fmt.allocPrint(
            emitter.arena,
            "{s} = sub {s} 0, {s}",
            .{ result_value, instruction_type, operand_value },
        ) catch unreachable,
        .Not => std.fmt.allocPrint(
            emitter.arena,
            "{s} = xor {s} {s}, 1",
            .{ result_value, instruction_type, operand_value },
        ) catch unreachable,
    };
    emitter.function_ir_builder.emitInstruction(instruction);

    return .{ .value = result_value };
}

pub fn emitLoweredBinaryOperation(
    emitter: *NodeEmitter,
    decision: lowering.lowering_types.BinaryOperationDecision,
    operand_type_id: typing.TypeId,
    left_value: Value,
    right_value: Value,
    lowered_program: *const lowering.LoweredProgram,
) Value {
    return switch (decision) {
        .PrimitiveOperation => |primitive_operation| {
            const llvm_ir_type = lowered_program.getLlvmIrType(operand_type_id);
            const operator_instruction = switch (primitive_operation) {
                .Add => "add",
                .Subtract => "sub",
                .Multiply => "mul",
                .Equal => "icmp eq",
                .NotEqual => "icmp ne",
                .LessThan => "icmp slt",
                .LessThanOrEqual => "icmp sle",
                .GreaterThan => "icmp sgt",
                .GreaterThanOrEqual => "icmp sge",
            };

            const result_value = emitter.function_symbol_generator.generateValueName();
            const instruction = std.fmt.allocPrint(
                emitter.arena,
                "{s} = {s} {s} {s}, {s}",
                .{ result_value, operator_instruction, llvm_ir_type, left_value, right_value },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(instruction);

            return result_value;
        },
        .UnionCaseIndexComparison => {
            const union_case_index_type = lowering.lowering_types.union_case_index_llvm_type;
            const operator_instruction = "icmp eq";

            // The case index is the first field of every case, so it can be loaded from the union pointer directly
            const union_case_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitLoad(union_case_value, left_value, union_case_index_type);

            const result_value = emitter.function_symbol_generator.generateValueName();
            const instruction = std.fmt.allocPrint(
                emitter.arena,
                "{s} = {s} {s} {s}, {s}",
                .{ result_value, operator_instruction, union_case_index_type, union_case_value, right_value },
            ) catch unreachable;
            emitter.function_ir_builder.emitInstruction(instruction);

            return result_value;
        },
        .StringConcatenate => emitter.runtime_call_emitter.emitStringConcatenateCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            emitter.emitStringParts(left_value),
            emitter.emitStringParts(right_value),
        ),
        .StringCompareEqual => emitter.runtime_call_emitter.emitStringCompareCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            emitter.emitStringParts(left_value),
            emitter.emitStringParts(right_value),
        ),
        .StringCompareNotEqual => compare_not_equal: {
            const equal_value = emitter.runtime_call_emitter.emitStringCompareCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                emitter.emitStringParts(left_value),
                emitter.emitStringParts(right_value),
            );
            const result_value = emitter.function_symbol_generator.generateValueName();
            emitter.function_ir_builder.emitInstruction(std.fmt.allocPrint(
                emitter.arena,
                "{s} = xor i1 {s}, 1",
                .{ result_value, equal_value },
            ) catch unreachable);
            break :compare_not_equal result_value;
        },
        .ZeroSizedCompareEqual,
        .ZeroSizedCompareNotEqual,
        .ShortCircuitAnd,
        .ShortCircuitOr,
        .CheckedDivide,
        => unreachable,
    };
}
