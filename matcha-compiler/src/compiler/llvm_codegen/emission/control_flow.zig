const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const values = @import("values.zig");

const Value = function_symbol_generator_module.Value;
const Label = function_symbol_generator_module.Label;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;
const LoopContext = node_emitter_module.LoopContext;

const LoopConstruct = struct {
    kind: enum { While, Loop },
    condition: ?*ast.Node,
    update: ?*ast.Node,
    body_block: *const ast.Block,
};

const DecisionConstruct = struct {
    subject: ?*const ast.Node,
    arms: []const DecisionArm,
    else_arm: ?*const ast.Node,
    exhaustive_without_else: bool = false,
};

const DecisionArm = struct {
    condition: DecisionArmCondition,
    body: *const ast.Node,
};

const DecisionArmCondition = union(enum) {
    Expression: *const ast.Node,
    Pattern: *const ast.Pattern,
};

/// Names the labels of a decision construct. An `if` has one arm, called `then`. The arms of a `match` are numbered.
const DecisionKind = enum {
    If,
    Match,
    SubjectlessMatch,

    fn constructName(self: @This()) []const u8 {
        return switch (self) {
            .If => "if",
            .Match => "match",
            .SubjectlessMatch => "subjectless_match",
        };
    }
};

const PhiIncoming = struct {
    label: Label,
    value: Value,
};

pub fn emitBlock(
    emitter: *NodeEmitter,
    block: ast.Block,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    for (block.statements) |statement| {
        _ = emitter.emitNode(&statement, lowered_program, environment);
    }

    if (block.result) |result_node| {
        return emitter.emitNode(result_node, lowered_program, environment);
    }
    // A result-less block is `zero_sized` in expression context (it evaluates to unit) but a statement in statement
    // context. We cannot distinguish the two here (no node id, so no type-table lookup), so we return `zero_sized`:
    // statement-context callers discard the result anyway, while expression-context callers need the accurate value.
    return .zero_sized;
}

pub fn emitReturnStatement(
    emitter: *NodeEmitter,
    return_statement: *const ast.ReturnStatement,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    if (return_statement.value) |return_value| {
        const return_value_runtime_representation = lowered_program
            .analyzed_program
            .runtime_representation_result
            .runtime_representation_by_node_id
            .get(return_value.id) orelse unreachable;

        const returned_value = emitter.emitNode(return_value, lowered_program, environment);

        if (!return_value_runtime_representation.hasRuntimeRepresentation()) {
            emitter.function_ir_builder.emitTerminatorInstruction("ret void");
            return .statement;
        }

        const return_instruction = std.fmt.allocPrint(
            emitter.arena,
            "ret {s} {s}",
            .{
                lowered_program.getLlvmIrType(environment.function_return_type_id),
                returned_value.expectValue(),
            },
        ) catch unreachable;
        emitter.function_ir_builder.emitTerminatorInstruction(return_instruction);
    } else {
        emitter.function_ir_builder.emitTerminatorInstruction("ret void");
    }
    return .statement;
}

pub fn emitIfStatement(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    if_statement: *const ast.IfStatement,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const decision_arms = [_]DecisionArm{.{
        .condition = .{ .Expression = if_statement.condition },
        .body = if_statement.then_branch,
    }};
    return emitDecisionConstruct(
        emitter,
        node,
        .{
            .subject = null,
            .arms = &decision_arms,
            .else_arm = null,
        },
        .If,
        lowered_program,
        environment,
    );
}

pub fn emitIfExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    if_expression: *const ast.IfExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const decision_arms = [_]DecisionArm{.{
        .condition = .{ .Expression = if_expression.condition },
        .body = if_expression.then_block,
    }};
    return emitDecisionConstruct(
        emitter,
        node,
        .{
            .subject = null,
            .arms = &decision_arms,
            .else_arm = if_expression.else_block,
        },
        .If,
        lowered_program,
        environment,
    );
}

pub fn emitMatchExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    match_expression: *const ast.MatchExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    var decision_arms = std.ArrayList(DecisionArm){};
    for (match_expression.arms) |*arm| {
        decision_arms.append(emitter.arena, .{
            .condition = .{ .Pattern = &arm.pattern },
            .body = arm.body_expression,
        }) catch unreachable;
    }

    const exhaustive_without_else = match_expression.else_arm_expression == null;

    return emitDecisionConstruct(
        emitter,
        node,
        .{
            .subject = match_expression.subject,
            .arms = decision_arms.items,
            .else_arm = match_expression.else_arm_expression,
            .exhaustive_without_else = exhaustive_without_else,
        },
        .Match,
        lowered_program,
        environment,
    );
}

pub fn emitSubjectlessMatchExpression(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    subjectless_match_expression: *const ast.SubjectlessMatchExpression,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    var decision_arms = std.ArrayList(DecisionArm){};
    for (subjectless_match_expression.arms) |arm| {
        decision_arms.append(emitter.arena, .{
            .condition = .{ .Expression = arm.condition },
            .body = arm.body_expression,
        }) catch unreachable;
    }

    return emitDecisionConstruct(
        emitter,
        node,
        .{
            .subject = null,
            .arms = decision_arms.items,
            .else_arm = subjectless_match_expression.else_arm_expression,
        },
        .SubjectlessMatch,
        lowered_program,
        environment,
    );
}

pub fn emitLoop(
    emitter: *NodeEmitter,
    loop: *const ast.Loop,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const body_block = switch (loop.body_block.kind) {
        .Block => |*block| block,
        else => unreachable,
    };

    return emitLoopConstruct(
        emitter,
        .{
            .kind = .Loop,
            .condition = null,
            .body_block = body_block,
            .update = null,
        },
        lowered_program,
        environment,
    );
}

pub fn emitWhile(
    emitter: *NodeEmitter,
    while_statement: *const ast.While,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const body_block = switch (while_statement.body_block.kind) {
        .Block => |*block| block,
        else => unreachable,
    };

    return emitLoopConstruct(
        emitter,
        .{
            .kind = .While,
            .condition = while_statement.condition,
            .body_block = body_block,
            .update = while_statement.update,
        },
        lowered_program,
        environment,
    );
}

pub fn emitForInArrayLoop(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    for_in: *const ast.ForIn,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    // Created before the iterable, so an outer construct gets a lower number than the constructs nested in it.
    const labels = emitter.function_symbol_generator.generateConstructLabels("for_in");
    const iterable_value = emitter.emitNode(for_in.iterable, lowered_program, environment).expectValue();

    const iterable_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(for_in.iterable.id) orelse unreachable;
    const element_type_id = switch (lowered_program.analyzed_program.type_store.getType(iterable_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = lowered_program.getLlvmIrType(element_type_id);
    const element_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(element_type_id) orelse unreachable;

    var item_address: ?function_symbol_generator_module.Address = null;
    if (element_runtime_representation.hasRuntimeRepresentation()) {
        const item_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
        const item_name = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(item_symbol_id).name;
        item_address = emitter.function_symbol_generator.generateBindingAddressName(item_name);
        builder.emitStackAllocation(item_address orelse unreachable, element_llvm_type); // don't
        environment.address_by_symbol_id.put(item_symbol_id, item_address orelse unreachable) catch unreachable;
    }

    const index_address = emitter.function_symbol_generator.generateSyntheticAddressName();
    builder.emitStackAllocation(index_address, "i64");
    builder.emitStore("0", index_address, "i64");

    const length_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        length_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        iterable_value,
        lowering.llvm_type.array_length_field_index,
    );

    const length_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(length_value, length_pointer_value, "i64");

    const data_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        data_pointer_value,
        lowering.llvm_type.array_llvm_type_name,
        iterable_value,
        lowering.llvm_type.array_data_field_index,
    );

    const data_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(data_value, data_pointer_value, "ptr");

    const loop_header_label = labels.role("header");
    const loop_body_label = labels.role("body");
    const loop_continue_label = labels.role("continue");
    const loop_exit_label = labels.role("exit");
    const previous_loop_context = environment.loop_context;
    environment.loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };

    builder.emitBranchInstruction(null, &.{loop_header_label});
    builder.emitLabel(loop_header_label);

    const current_index_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(current_index_value, index_address, "i64");

    const within_bounds_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.arena,
        "{s} = icmp slt i64 {s}, {s}",
        .{ within_bounds_value, current_index_value, length_value },
    ) catch unreachable);
    builder.emitBranchInstruction(within_bounds_value, &.{ loop_body_label, loop_exit_label });

    builder.emitLabel(loop_body_label);

    if (item_address) |address| {
        const element_pointer_value = emitter.function_symbol_generator.generateValueName();
        builder.emitElementPointer(element_pointer_value, element_llvm_type, data_value, current_index_value);
        const element_value = emitter.function_symbol_generator.generateValueName();
        builder.emitLoad(element_value, element_pointer_value, element_llvm_type);
        builder.emitStore(element_value, address, element_llvm_type);
    }

    const body_block = switch (for_in.body_block.kind) {
        .Block => |block| block,
        else => unreachable,
    };
    _ = emitBlock(emitter, body_block, lowered_program, environment);

    builder.emitBranchInstruction(null, &.{loop_continue_label});
    builder.emitLabel(loop_continue_label);

    const loop_index_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(loop_index_value, index_address, "i64");
    const next_index_value = emitter.function_symbol_generator.generateValueName();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.arena,
        "{s} = add i64 {s}, 1",
        .{ next_index_value, loop_index_value },
    ) catch unreachable);
    builder.emitStore(next_index_value, index_address, "i64");
    builder.emitBranchInstruction(null, &.{loop_header_label});

    builder.emitLabel(loop_exit_label);
    environment.loop_context = previous_loop_context;

    return .statement;
}

fn emitLoopConstruct(
    emitter: *NodeEmitter,
    loop_construct: LoopConstruct,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    const labels = emitter.function_symbol_generator.generateConstructLabels(switch (loop_construct.kind) {
        .While => "while",
        .Loop => "loop",
    });
    const loop_header_label = labels.role("header");
    const loop_body_label = labels.role("body");
    const loop_continue_label = labels.role("continue");
    const loop_exit_label = labels.role("exit");
    const previous_loop_context = environment.loop_context;
    environment.loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };

    // Loop header
    builder.emitBranchInstruction(null, &.{loop_header_label});
    builder.emitLabel(loop_header_label);
    if (loop_construct.condition) |condition| {
        const condition_value = emitter.emitNode(condition, lowered_program, environment);
        builder.emitBranchInstruction(condition_value.expectValue(), &.{ loop_body_label, loop_exit_label });
    } else {
        builder.emitBranchInstruction(null, &.{loop_body_label});
    }

    // Loop body
    builder.emitLabel(loop_body_label);
    _ = emitBlock(emitter, loop_construct.body_block.*, lowered_program, environment);
    builder.emitBranchInstruction(null, &.{loop_continue_label});

    // Loop continue
    builder.emitLabel(loop_continue_label);
    if (loop_construct.update) |update| {
        _ = emitter.emitNode(update, lowered_program, environment);
    }
    builder.emitBranchInstruction(null, &.{loop_header_label});

    builder.emitLabel(loop_exit_label);
    environment.loop_context = previous_loop_context;

    return .statement;
}

fn emitDecisionConstruct(
    emitter: *NodeEmitter,
    node: *const ast.Node,
    decision_construct: DecisionConstruct,
    decision_kind: DecisionKind,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    // Created before the subject, so an outer construct gets a lower number than the constructs nested in it.
    const labels = emitter.function_symbol_generator.generateConstructLabels(decision_kind.constructName());
    var subject_value: ?Value = null;
    var subject_type_id: ?typing.TypeId = null;

    if (decision_construct.subject) |subject| {
        subject_value = emitter.emitNode(subject, lowered_program, environment).expectValue();
        subject_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(subject.id).?;
    }

    const result_type_id = lowered_program.analyzed_program.type_id_by_node_id.get(node.id).?;
    const result_type_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(result_type_id).?;
    const produces_value = result_type_runtime_representation.hasRuntimeRepresentation();
    const continue_label = labels.role("end");
    var incoming_values = std.ArrayList(PhiIncoming){};
    var continue_reachable = false;

    const else_label = if (decision_construct.else_arm != null)
        labels.role("else")
    else
        null;

    if (decision_construct.arms.len == 0 and decision_construct.else_arm != null) {
        const else_value = emitter.emitNode(decision_construct.else_arm.?, lowered_program, environment);
        if (builder.currentLabel()) |exit_label| {
            continue_reachable = true;
            if (produces_value) {
                incoming_values.append(emitter.arena, .{
                    .label = exit_label,
                    .value = else_value.expectValue(),
                }) catch unreachable;
            }
            builder.emitBranchInstruction(null, &.{continue_label});
        }
    } else {
        for (decision_construct.arms, 0..) |arm, index| {
            const arm_label = switch (decision_kind) {
                .If => labels.role("then"),
                .Match, .SubjectlessMatch => labels.arm(index),
            };
            const is_last_arm = index + 1 == decision_construct.arms.len;
            const false_branches_to_continue = is_last_arm and
                else_label == null and
                !decision_construct.exhaustive_without_else;
            const false_label = if (!is_last_arm)
                labels.armCondition(index + 1)
            else if (else_label) |label|
                label
            else if (decision_construct.exhaustive_without_else)
                null
            else
                continue_label;

            if (false_branches_to_continue) {
                continue_reachable = true;
            }

            const optional_union_case_index: ?u32 = switch (arm.condition) {
                .Expression => null,
                .Pattern => |pattern| switch (pattern.kind) {
                    .Case => lowered_program.analyzed_program.union_case_index_by_pattern_id.get(pattern.id).?,
                    else => null,
                },
            };
            if (is_last_arm and decision_construct.exhaustive_without_else and else_label == null) {
                builder.emitBranchInstruction(null, &.{arm_label});
            } else {
                const condition_value = switch (arm.condition) {
                    .Expression => |expression| emitter.emitNode(expression, lowered_program, environment).expectValue(),
                    .Pattern => |pattern| values.emitLoweredBinaryOperation(
                        emitter,
                        lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
                        subject_type_id.?,
                        subject_value.?,
                        emitPatternValue(emitter, pattern, lowered_program),
                        lowered_program,
                    ),
                };
                builder.emitBranchInstruction(condition_value, &.{ arm_label, false_label.? });
            }

            builder.emitLabel(arm_label);
            if (optional_union_case_index) |union_case_index| {
                if (arm.condition.Pattern.kind.Case.binding) |payload_binding| {
                    emitCasePatternBinding(
                        emitter,
                        payload_binding,
                        subject_type_id.?,
                        subject_value.?,
                        union_case_index,
                        lowered_program,
                        environment,
                    );
                }
            }

            const arm_value = emitter.emitNode(arm.body, lowered_program, environment);
            if (builder.currentLabel()) |exit_label| {
                continue_reachable = true;
                if (produces_value) {
                    incoming_values.append(emitter.arena, .{
                        .label = exit_label,
                        .value = arm_value.expectValue(),
                    }) catch unreachable;
                }
                builder.emitBranchInstruction(null, &.{continue_label});
            }

            if (false_label) |next_label| {
                if (!false_branches_to_continue) {
                    builder.emitLabel(next_label);
                }
            }
        }

        if (decision_construct.else_arm) |else_arm| {
            const else_value = emitter.emitNode(else_arm, lowered_program, environment);
            if (builder.currentLabel()) |exit_label| {
                continue_reachable = true;
                if (produces_value) {
                    incoming_values.append(emitter.arena, .{
                        .label = exit_label,
                        .value = else_value.expectValue(),
                    }) catch unreachable;
                }
                builder.emitBranchInstruction(null, &.{continue_label});
            }
        }
    }

    if (!continue_reachable) {
        // Every path through the construct diverged; the cursor is already
        // null, so the poison value below is never used in emitted code.
        return if (produces_value)
            .{ .value = emitter.function_symbol_generator.generateValueName() }
        else
            .zero_sized;
    }

    builder.emitLabel(continue_label);
    if (!produces_value) {
        return .zero_sized;
    }
    if (incoming_values.items.len == 0) {
        return .{ .value = emitter.function_symbol_generator.generateValueName() };
    }
    if (incoming_values.items.len == 1) {
        return .{ .value = incoming_values.items[0].value };
    }

    var phi_incoming_buffer = std.ArrayList(u8){};
    for (incoming_values.items, 0..) |incoming, index| {
        if (index > 0) {
            phi_incoming_buffer.writer(emitter.arena).print(", ", .{}) catch unreachable;
        }
        phi_incoming_buffer.writer(emitter.arena).print(
            "[{s}, %{s}]",
            .{ incoming.value, incoming.label },
        ) catch unreachable;
    }

    const result_value = emitter.function_symbol_generator.generateValueName();
    const phi_instruction = std.fmt.allocPrint(
        emitter.arena,
        "{s} = phi {s} {s}",
        .{
            result_value,
            lowered_program.getLlvmIrType(result_type_id),
            phi_incoming_buffer.items,
        },
    ) catch unreachable;
    builder.emitInstruction(phi_instruction);

    return .{ .value = result_value };
}

// Binds the payload of the matched case to the binding of its case pattern. A payload without a runtime
// representation gets no address, because reading the binding never loads it.
fn emitCasePatternBinding(
    emitter: *NodeEmitter,
    payload_binding: ast.PayloadBinding,
    union_type_id: typing.TypeId,
    union_value: Value,
    case_index: u32,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) void {
    const builder = emitter.function_ir_builder;
    const payload_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(payload_binding.id).?;
    const payload_type_id = lowered_program.analyzed_program.type_id_by_symbol_id.get(payload_symbol_id).?;
    const payload_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(payload_type_id).?;
    if (!payload_runtime_representation.hasRuntimeRepresentation()) {
        return;
    }

    const payload_name = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(payload_symbol_id).name;
    const payload_address = emitter.function_symbol_generator.generateBindingAddressName(payload_name);
    const payload_llvm_type = lowered_program.getLlvmIrType(payload_type_id);
    builder.emitStackAllocation(payload_address, payload_llvm_type);
    environment.address_by_symbol_id.put(payload_symbol_id, payload_address) catch unreachable;

    const union_case_layout = lowered_program.union_layout_by_type_id.get(union_type_id).?.cases[case_index];
    const payload_pointer_value = emitter.function_symbol_generator.generateValueName();
    builder.emitFieldPointer(
        payload_pointer_value,
        union_case_layout.llvm_type_name,
        union_value,
        lowering.lowering_types.union_payload_field_index,
    );
    const payload_value = emitter.function_symbol_generator.generateValueName();
    builder.emitLoad(payload_value, payload_pointer_value, payload_llvm_type);
    builder.emitStore(payload_value, payload_address, payload_llvm_type);
}

fn emitPatternValue(
    emitter: *NodeEmitter,
    pattern: *const ast.Pattern,
    lowered_program: *const lowering.LoweredProgram,
) Value {
    return switch (pattern.kind) {
        .IntegerLiteral => |integer_literal| std.fmt.allocPrint(
            emitter.arena,
            "{d}",
            .{integer_literal.value()},
        ) catch unreachable,
        .BooleanLiteral => |token| if (token.kind.BooleanLiteral) "1" else "0",
        .StringLiteral => |token| emitter.string_literal_emitter.emitStringLiteralValue(
            emitter.string_literal_pool,
            pattern.id,
            token.kind.StringLiteral,
            emitter.function_symbol_generator,
            emitter.function_ir_builder,
        ),
        // A case pattern matches when the subject stores the case index of the pattern, so the case index is the value
        // that `UnionCaseIndexComparison` compares the loaded case index with.
        .Case => std.fmt.allocPrint(emitter.arena, "{d}", .{
            lowered_program.analyzed_program.union_case_index_by_pattern_id.get(pattern.id).?,
        }) catch unreachable,
    };
}
