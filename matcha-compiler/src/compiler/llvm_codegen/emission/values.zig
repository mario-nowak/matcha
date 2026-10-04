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
) !EmissionResult {
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
    const value = try emitter.function_symbol_generator.generateValueName();
    try emitter.function_ir_builder.emitLoad(value, address, llvm_ir_type);

    return .{ .value = value };
}

pub fn emitBinaryExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    binary_expression: *const ast.BinaryExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const decision = lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable;
    switch (decision) {
        .short_circuit_and => return emitShortCircuitOperation(emitter, binary_expression, .@"and", lowered_program, environment),
        .short_circuit_or => return emitShortCircuitOperation(emitter, binary_expression, .@"or", lowered_program, environment),
        else => {},
    }

    const left_value = try emitter.emitNode(binary_expression.left, lowered_program, environment);
    const right_value = try emitter.emitNode(binary_expression.right, lowered_program, environment);
    const left_operand_type = lowered_program.analyzed_program.type_id_by_node_id.get(binary_expression.left.id).?;

    // Unit operands have no runtime value. Their side effects already ran above, so the result is a constant.
    switch (decision) {
        .zero_sized_compare_equal => return .{ .value = "1" },
        .zero_sized_compare_not_equal => return .{ .value = "0" },
        .checked_divide => return .{ .value = try emitCheckedDivision(
            emitter,
            binary_expression.operator_token.line,
            binary_expression.operator_token.column,
            left_value.expectValue(),
            right_value.expectValue(),
        ) },
        else => {},
    }

    return .{ .value = try emitLoweredBinaryOperation(
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
) !Value {
    const builder = emitter.function_ir_builder;
    const labels = try emitter.function_symbol_generator.generateConstructLabels("division");
    const zero_divisor_label = try labels.role("zero_divisor");
    const nonzero_divisor_label = try labels.role("nonzero_divisor");
    const overflow_label = try labels.role("overflow");
    const no_overflow_label = try labels.role("no_overflow");

    const zero_divisor_value = try emitter.function_symbol_generator.generateValueName();
    try builder.emitInstruction(try std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, 0", .{ zero_divisor_value, divisor_value }));
    try builder.emitBranchInstruction(zero_divisor_value, &.{ zero_divisor_label, nonzero_divisor_label });

    try builder.emitLabel(zero_divisor_label);
    try emitter.runtime_call_emitter.emitPanicDivisionByZeroCall(builder, line, column);
    try builder.emitTerminatorInstruction("unreachable");

    try builder.emitLabel(nonzero_divisor_label);
    const minimum_dividend_value = try emitter.function_symbol_generator.generateValueName();
    try builder.emitInstruction(try std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, {d}", .{ minimum_dividend_value, dividend_value, std.math.minInt(i64) }));
    const negative_one_divisor_value = try emitter.function_symbol_generator.generateValueName();
    try builder.emitInstruction(try std.fmt.allocPrint(emitter.arena, "{s} = icmp eq i64 {s}, -1", .{ negative_one_divisor_value, divisor_value }));
    const overflow_value = try emitter.function_symbol_generator.generateValueName();
    try builder.emitInstruction(try std.fmt.allocPrint(emitter.arena, "{s} = and i1 {s}, {s}", .{ overflow_value, minimum_dividend_value, negative_one_divisor_value }));
    try builder.emitBranchInstruction(overflow_value, &.{ overflow_label, no_overflow_label });

    try builder.emitLabel(overflow_label);
    try emitter.runtime_call_emitter.emitPanicDivisionOverflowCall(builder, line, column);
    try builder.emitTerminatorInstruction("unreachable");

    try builder.emitLabel(no_overflow_label);
    const quotient_value = try emitter.function_symbol_generator.generateValueName();
    try builder.emitInstruction(try std.fmt.allocPrint(emitter.arena, "{s} = sdiv i64 {s}, {s}", .{ quotient_value, dividend_value, divisor_value }));

    return quotient_value;
}

// Emits the right operand only when the left operand does not decide the result already. The result is a phi of
// the deciding constant (false for `and`, true for `or`) and the value of the right operand.
fn emitShortCircuitOperation(
    emitter: *NodeEmitter,
    binary_expression: *const ast.BinaryExpression,
    operator: enum { @"and", @"or" },
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const builder = emitter.function_ir_builder;
    const construct_name, const deciding_value = switch (operator) {
        .@"and" => .{ "and", "0" },
        .@"or" => .{ "or", "1" },
    };
    const labels = try emitter.function_symbol_generator.generateConstructLabels(construct_name);
    const end_label = try labels.role("end");
    const right_label = try labels.role("right");

    const left_value = (try emitter.emitNode(binary_expression.left, lowered_program, environment)).expectValue();
    // The phi needs the block where the left operand ended, which is not the start block when the operand branches.
    const left_exit_label = builder.currentLabel() orelse unreachable;
    switch (operator) {
        .@"and" => try builder.emitBranchInstruction(left_value, &.{ right_label, end_label }),
        .@"or" => try builder.emitBranchInstruction(left_value, &.{ end_label, right_label }),
    }

    try builder.emitLabel(right_label);
    const right_value = (try emitter.emitNode(binary_expression.right, lowered_program, environment)).expectValue();
    const right_exit_label = builder.currentLabel() orelse unreachable;
    try builder.emitBranchInstruction(null, &.{end_label});

    try builder.emitLabel(end_label);
    const result_value = try emitter.function_symbol_generator.generateValueName();
    const phi_instruction = try std.fmt.allocPrint(
        emitter.arena,
        "{s} = phi i1 [{s}, %{s}], [{s}, %{s}]",
        .{ result_value, deciding_value, left_exit_label, right_value, right_exit_label },
    );
    try builder.emitInstruction(phi_instruction);

    return .{ .value = result_value };
}

pub fn emitUnaryExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    unary_expression: *const ast.UnaryExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) !EmissionResult {
    const operand_value = (try emitter.emitNode(unary_expression.operand, lowered_program, environment)).expectValue();
    const result_value = try emitter.function_symbol_generator.generateValueName();
    const operation_type = lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?;
    const instruction_type = lowered_program.getLlvmIrType(operation_type);
    const instruction = switch (unary_expression.operator) {
        .negate => try std.fmt.allocPrint(
            emitter.arena,
            "{s} = sub {s} 0, {s}",
            .{ result_value, instruction_type, operand_value },
        ),
        .not => try std.fmt.allocPrint(
            emitter.arena,
            "{s} = xor {s} {s}, 1",
            .{ result_value, instruction_type, operand_value },
        ),
    };
    try emitter.function_ir_builder.emitInstruction(instruction);

    return .{ .value = result_value };
}

pub fn emitLoweredBinaryOperation(
    emitter: *NodeEmitter,
    decision: lowering.lowering_types.BinaryOperationDecision,
    operand_type_id: typing.TypeId,
    left_value: Value,
    right_value: Value,
    lowered_program: *const lowering.LoweredProgram,
) !Value {
    return switch (decision) {
        .primitive_operation => |primitive_operation| {
            const llvm_ir_type = lowered_program.getLlvmIrType(operand_type_id);
            const operator_instruction = switch (primitive_operation) {
                .add => "add",
                .subtract => "sub",
                .multiply => "mul",
                .equal => "icmp eq",
                .not_equal => "icmp ne",
                .less_than => "icmp slt",
                .less_than_or_equal => "icmp sle",
                .greater_than => "icmp sgt",
                .greater_than_or_equal => "icmp sge",
            };

            const result_value = try emitter.function_symbol_generator.generateValueName();
            const instruction = try std.fmt.allocPrint(
                emitter.arena,
                "{s} = {s} {s} {s}, {s}",
                .{ result_value, operator_instruction, llvm_ir_type, left_value, right_value },
            );
            try emitter.function_ir_builder.emitInstruction(instruction);

            return result_value;
        },
        .union_case_index_comparison => {
            const union_case_index_type = lowering.lowering_types.union_case_index_llvm_type;
            const operator_instruction = "icmp eq";

            // The case index is the first field of every case, so it can be loaded from the union pointer directly
            const union_case_value = try emitter.function_symbol_generator.generateValueName();
            try emitter.function_ir_builder.emitLoad(union_case_value, left_value, union_case_index_type);

            const result_value = try emitter.function_symbol_generator.generateValueName();
            const instruction = try std.fmt.allocPrint(
                emitter.arena,
                "{s} = {s} {s} {s}, {s}",
                .{ result_value, operator_instruction, union_case_index_type, union_case_value, right_value },
            );
            try emitter.function_ir_builder.emitInstruction(instruction);

            return result_value;
        },
        .string_concatenate => try emitter.runtime_call_emitter.emitStringConcatenateCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            try emitter.emitStringParts(left_value),
            try emitter.emitStringParts(right_value),
        ),
        .string_compare_equal => try emitter.runtime_call_emitter.emitStringCompareCall(
            emitter.function_ir_builder,
            emitter.function_symbol_generator,
            try emitter.emitStringParts(left_value),
            try emitter.emitStringParts(right_value),
        ),
        .string_compare_not_equal => compare_not_equal: {
            const equal_value = try emitter.runtime_call_emitter.emitStringCompareCall(
                emitter.function_ir_builder,
                emitter.function_symbol_generator,
                try emitter.emitStringParts(left_value),
                try emitter.emitStringParts(right_value),
            );
            const result_value = try emitter.function_symbol_generator.generateValueName();
            try emitter.function_ir_builder.emitInstruction(try std.fmt.allocPrint(
                emitter.arena,
                "{s} = xor i1 {s}, 1",
                .{ result_value, equal_value },
            ));
            break :compare_not_equal result_value;
        },
        .zero_sized_compare_equal,
        .zero_sized_compare_not_equal,
        .short_circuit_and,
        .short_circuit_or,
        .checked_divide,
        => unreachable,
    };
}
