const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");

const function_symbol_generator_module = @import("function_symbol_generator.zig");
const node_emitter_module = @import("node_emitter.zig");
const values = @import("values.zig");

const Register = function_symbol_generator_module.Register;
const Label = function_symbol_generator_module.Label;
const NodeEmitter = node_emitter_module.NodeEmitter;
const EmissionResult = node_emitter_module.EmissionResult;
const Environment = node_emitter_module.Environment;
const LoopContext = node_emitter_module.LoopContext;

const LoopConstruct = struct {
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

pub fn emitReturn(
    emitter: *NodeEmitter,
    return_statement: *const ast.Return,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    if (return_statement.value) |return_value| {
        const return_value_runtime_representation = lowered_program
            .analyzed_program
            .runtime_representation_result
            .runtime_representation_by_node_id
            .get(return_value.id) orelse unreachable;

        const value_register = emitter.emitNode(return_value, lowered_program, environment);

        if (!return_value_runtime_representation.hasRuntimeRepresentation()) {
            emitter.function_ir_builder.emitTerminatorInstruction("ret void");
            return .statement;
        }

        const return_instruction = std.fmt.allocPrint(
            emitter.allocator,
            "ret {s} {s}",
            .{
                lowered_program.getLlvmIrType(environment.function_return_type_id),
                value_register.expectRegister(),
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
        .condition = if_statement.condition,
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
        .{
            .arm = "then",
            .else_arm = "else",
            .next = "next",
            .continue_label = "continue",
        },
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
        .condition = if_expression.condition,
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
        .{
            .arm = "then",
            .else_arm = "else",
            .next = "next",
            .continue_label = "continue",
        },
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
    defer decision_arms.deinit(emitter.allocator);
    for (match_expression.arms) |arm| {
        decision_arms.append(emitter.allocator, .{
            .condition = arm.pattern_or_condition,
            .body = arm.body,
        }) catch unreachable;
    }

    const exhaustive_without_else = if (match_expression.subject) |subject|
        match_expression.else_arm == null and
            lowered_program.analyzed_program.type_by_node_id.get(subject.id).? == lowered_program.analyzed_program.type_store.boolean_type_id
    else
        false;

    return emitDecisionConstruct(
        emitter,
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
    const iterable_register = emitter.emitNode(for_in.iterable, lowered_program, environment).expectRegister();

    const iterable_type_id = lowered_program.analyzed_program.type_by_node_id.get(for_in.iterable.id) orelse unreachable;
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

    var item_storage: ?function_symbol_generator_module.Storage = null;
    if (element_runtime_representation.hasRuntimeRepresentation()) {
        const item_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
        item_storage = emitter.function_symbol_generator.generateStorage();
        builder.emitAlloca(item_storage orelse unreachable, element_llvm_type); // don't
        environment.storage_by_symbol_id.put(item_symbol_id, item_storage orelse unreachable) catch unreachable;
    }

    const index_storage = emitter.function_symbol_generator.generateStorage();
    builder.emitAlloca(index_storage, "i64");
    builder.emitStore("0", index_storage, "i64");

    const length_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, iterable_register },
    ) catch unreachable);

    const length_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(length_register, length_pointer_register, "i64");

    const data_pointer_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, iterable_register },
    ) catch unreachable);

    const data_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(data_register, data_pointer_register, "ptr");

    const loop_header_label = emitter.function_symbol_generator.generateLabel("loop_header");
    const loop_body_label = emitter.function_symbol_generator.generateLabel("loop_body");
    const loop_continue_label = emitter.function_symbol_generator.generateLabel("loop_continue");
    const loop_exit_label = emitter.function_symbol_generator.generateLabel("loop_exit");
    const previous_loop_context = environment.loop_context;
    environment.loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };

    builder.emitBranchInstruction(null, &.{loop_header_label});
    builder.emitLabel(loop_header_label);

    const current_index_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(current_index_register, index_storage, "i64");

    const within_bounds_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = icmp slt i64 {s}, {s}",
        .{ within_bounds_register, current_index_register, length_register },
    ) catch unreachable);
    builder.emitBranchInstruction(within_bounds_register, &.{ loop_body_label, loop_exit_label });

    builder.emitLabel(loop_body_label);

    if (item_storage) |storage| {
        const element_pointer_register = emitter.function_symbol_generator.generateRegister();
        builder.emitInstruction(std.fmt.allocPrint(
            emitter.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
            .{ element_pointer_register, element_llvm_type, data_register, current_index_register },
        ) catch unreachable);
        const element_register = emitter.function_symbol_generator.generateRegister();
        builder.emitLoad(element_register, element_pointer_register, element_llvm_type);
        builder.emitStore(element_register, storage, element_llvm_type);
    }

    const body_block = switch (for_in.body_block.kind) {
        .Block => |block| block,
        else => unreachable,
    };
    _ = emitBlock(emitter, body_block, lowered_program, environment);

    builder.emitBranchInstruction(null, &.{loop_continue_label});
    builder.emitLabel(loop_continue_label);

    const loop_index_register = emitter.function_symbol_generator.generateRegister();
    builder.emitLoad(loop_index_register, index_storage, "i64");
    const next_index_register = emitter.function_symbol_generator.generateRegister();
    builder.emitInstruction(std.fmt.allocPrint(
        emitter.allocator,
        "{s} = add i64 {s}, 1",
        .{ next_index_register, loop_index_register },
    ) catch unreachable);
    builder.emitStore(next_index_register, index_storage, "i64");
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
    const loop_header_label = emitter.function_symbol_generator.generateLabel("loop_header");
    const loop_body_label = emitter.function_symbol_generator.generateLabel("loop_body");
    const loop_continue_label = emitter.function_symbol_generator.generateLabel("loop_continue");
    const loop_exit_label = emitter.function_symbol_generator.generateLabel("loop_exit");
    const previous_loop_context = environment.loop_context;
    environment.loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };

    // Loop header
    builder.emitBranchInstruction(null, &.{loop_header_label});
    builder.emitLabel(loop_header_label);
    if (loop_construct.condition) |condition| {
        const condition_register = emitter.emitNode(condition, lowered_program, environment);
        builder.emitBranchInstruction(condition_register.expectRegister(), &.{ loop_body_label, loop_exit_label });
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
    label_names: DecisionLabelNames,
    lowered_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const builder = emitter.function_ir_builder;
    var subject_register: ?Register = null;
    var subject_type_id: ?typing.TypeId = null;

    if (decision_construct.subject) |subject| {
        subject_register = emitter.emitNode(subject, lowered_program, environment).expectRegister();
        subject_type_id = lowered_program.analyzed_program.type_by_node_id.get(subject.id).?;
    }

    const result_type_id = lowered_program.analyzed_program.type_by_node_id.get(node.id).?;
    const result_type_runtime_representation = lowered_program
        .analyzed_program
        .runtime_representation_result
        .runtime_representation_by_type_id
        .get(result_type_id) orelse undefined;
    // TODO:
    const produces_value = result_type_runtime_representation.hasRuntimeRepresentation();
    const continue_label = emitter.function_symbol_generator.generateLabel(label_names.continue_label);
    var incoming_values = std.ArrayList(PhiIncoming){};
    defer incoming_values.deinit(emitter.allocator);
    var continue_reachable = false;

    const else_label = if (decision_construct.else_arm != null)
        emitter.function_symbol_generator.generateLabel(label_names.else_arm)
    else
        null;

    if (decision_construct.arms.len == 0 and decision_construct.else_arm != null) {
        const else_register = emitter.emitNode(decision_construct.else_arm.?, lowered_program, environment);
        if (builder.currentLabel()) |exit_label| {
            continue_reachable = true;
            if (produces_value) {
                incoming_values.append(emitter.allocator, .{
                    .label = exit_label,
                    .register = else_register.expectRegister(),
                }) catch unreachable;
            }
            builder.emitBranchInstruction(null, &.{continue_label});
        }
    } else {
        for (decision_construct.arms, 0..) |arm, index| {
            const arm_label = emitter.function_symbol_generator.generateLabel(label_names.arm);
            const is_last_arm = index + 1 == decision_construct.arms.len;
            const false_branches_to_continue = is_last_arm and
                else_label == null and
                !decision_construct.exhaustive_without_else;
            const false_label = if (!is_last_arm)
                emitter.function_symbol_generator.generateLabel(label_names.next)
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
                builder.emitBranchInstruction(null, &.{arm_label});
            } else if (decision_construct.subject != null) {
                const pattern_register = emitter.emitNode(arm.condition, lowered_program, environment);
                const comparison_register = values.emitLoweredBinaryOperation(
                    emitter,
                    lowered_program.binary_operation_decision_by_node_id.get(node.id) orelse unreachable,
                    subject_type_id.?,
                    subject_register.?,
                    pattern_register.expectRegister(),
                    lowered_program,
                );
                builder.emitBranchInstruction(comparison_register, &.{ arm_label, false_label.? });
            } else {
                const condition_register = emitter.emitNode(arm.condition, lowered_program, environment);
                builder.emitBranchInstruction(condition_register.expectRegister(), &.{ arm_label, false_label.? });
            }

            builder.emitLabel(arm_label);
            const arm_register = emitter.emitNode(arm.body, lowered_program, environment);
            if (builder.currentLabel()) |exit_label| {
                continue_reachable = true;
                if (produces_value) {
                    incoming_values.append(emitter.allocator, .{
                        .label = exit_label,
                        .register = arm_register.expectRegister(),
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
            const else_register = emitter.emitNode(else_arm, lowered_program, environment);
            if (builder.currentLabel()) |exit_label| {
                continue_reachable = true;
                if (produces_value) {
                    incoming_values.append(emitter.allocator, .{
                        .label = exit_label,
                        .register = else_register.expectRegister(),
                    }) catch unreachable;
                }
                builder.emitBranchInstruction(null, &.{continue_label});
            }
        }
    }

    if (!continue_reachable) {
        // Every path through the construct diverged; the cursor is already
        // null, so the poison register below is never used in emitted code.
        return if (produces_value)
            .{ .register = emitter.function_symbol_generator.generateRegister() }
        else
            .zero_sized;
    }

    builder.emitLabel(continue_label);
    if (!produces_value) {
        return .zero_sized;
    }
    if (incoming_values.items.len == 0) {
        return .{ .register = emitter.function_symbol_generator.generateRegister() };
    }
    if (incoming_values.items.len == 1) {
        return .{ .register = incoming_values.items[0].register };
    }

    var phi_incoming_buffer = std.ArrayList(u8){};
    defer phi_incoming_buffer.deinit(emitter.allocator);
    for (incoming_values.items, 0..) |incoming, index| {
        if (index > 0) {
            phi_incoming_buffer.writer(emitter.allocator).print(", ", .{}) catch unreachable;
        }
        phi_incoming_buffer.writer(emitter.allocator).print(
            "[{s}, %{s}]",
            .{ incoming.register, incoming.label },
        ) catch unreachable;
    }

    const result_register = emitter.function_symbol_generator.generateRegister();
    const phi_instruction = std.fmt.allocPrint(
        emitter.allocator,
        "{s} = phi {s} {s}",
        .{
            result_register,
            lowered_program.getLlvmIrType(result_type_id),
            phi_incoming_buffer.items,
        },
    ) catch unreachable;
    builder.emitInstruction(phi_instruction);

    return .{ .register = result_register };
}
