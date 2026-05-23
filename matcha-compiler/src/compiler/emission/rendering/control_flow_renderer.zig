const std = @import("std");
const ast = @import("ast");
const typing = @import("typing");
const lowering = @import("lowering");
const function_emission = @import("function_emission");
const support = @import("node_rendering_support.zig");

const Register = function_emission.Register;
const Label = function_emission.Label;
pub const LoopConstruct = struct {
    condition: ?*ast.Node,
    update: ?*ast.Node,
    body_block: *ast.Block,
};

pub const DecisionConstruct = struct {
    subject: ?*const ast.Node,
    arms: []const DecisionArm,
    else_arm: ?*const ast.Node,
    exhaustive_without_else: bool = false,
};

pub const DecisionArm = struct {
    condition: *const ast.Node,
    body: *const ast.Node,
};

pub const DecisionLabelNames = struct {
    arm: []const u8,
    else_arm: []const u8,
    next: []const u8,
    continue_label: []const u8,
};

const PhiIncoming = struct {
    label: Label,
    register: Register,
};

const LoopContext = support.LoopContext;
const Environment = support.Environment;
const EmissionResult = support.EmissionResult;

pub fn emitForInArrayLoop(
    self: anytype,
    node: *const ast.Node,
    for_in: *const ast.ForIn,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const iterable_result = self.emitNode(
        for_in.iterable,
        entry_label,
        typed_program,
        environment,
    );
    if (iterable_result.exit_label == null) {
        return .{ .exit_label = null, .register = null };
    }

    const iterable_type_id = typed_program.analyzed_program.type_by_node_id.get(for_in.iterable.id) orelse unreachable;
    const element_type_id = switch (typed_program.analyzed_program.type_store.getType(iterable_type_id)) {
        .Array => |id| id,
        else => unreachable,
    };
    const element_llvm_type = typed_program.llvmIrType(element_type_id);

    const item_symbol_id = typed_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
    const item_storage = self.function_symbol_generator.generateStorage();
    self.function_ir_builder.emitAlloca(item_storage, element_llvm_type);
    environment.storage_by_symbol_id.put(item_symbol_id, item_storage) catch unreachable;

    const index_storage = self.function_symbol_generator.generateStorage();
    self.function_ir_builder.emitAlloca(index_storage, "i64");
    self.function_ir_builder.emitStore("0", index_storage, "i64");

    const length_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 0",
        .{ length_pointer_register, iterable_result.register orelse unreachable },
    ) catch unreachable);

    const length_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(length_register, length_pointer_register, "i64");

    const data_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds %Array, ptr {s}, i32 0, i32 2",
        .{ data_pointer_register, iterable_result.register orelse unreachable },
    ) catch unreachable);

    const data_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(data_register, data_pointer_register, "ptr");

    const loop_header_label = self.function_symbol_generator.generateLabel("loop_header");
    const loop_body_label = self.function_symbol_generator.generateLabel("loop_body");
    const loop_continue_label = self.function_symbol_generator.generateLabel("loop_continue");
    const loop_exit_label = self.function_symbol_generator.generateLabel("loop_exit");
    const previous_loop_context = environment.loop_context;
    const loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };
    environment.loop_context = loop_context;

    self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
    self.function_ir_builder.emitLabel(loop_header_label);

    const current_index_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(current_index_register, index_storage, "i64");

    const within_bounds_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = icmp slt i64 {s}, {s}",
        .{ within_bounds_register, current_index_register, length_register },
    ) catch unreachable);
    self.function_ir_builder.emitBranchInstruction(within_bounds_register, &.{ loop_body_label, loop_exit_label });

    self.function_ir_builder.emitLabel(loop_body_label);

    const element_pointer_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
        .{ element_pointer_register, element_llvm_type, data_register, current_index_register },
    ) catch unreachable);

    const element_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(element_register, element_pointer_register, element_llvm_type);
    self.function_ir_builder.emitStore(element_register, item_storage, element_llvm_type);

    const body_block = switch (for_in.body_block.kind) {
        .Block => |block| block,
        else => unreachable,
    };
    const body_result = self.emitBlock(body_block, loop_body_label, typed_program, environment);

    if (body_result.exit_label != null) {
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_continue_label});
    }
    self.function_ir_builder.emitLabel(loop_continue_label);

    const loop_index_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitLoad(loop_index_register, index_storage, "i64");
    const next_index_register = self.function_symbol_generator.generateRegister();
    self.function_ir_builder.emitInstruction(std.fmt.allocPrint(
        self.allocator,
        "{s} = add i64 {s}, 1",
        .{ next_index_register, loop_index_register },
    ) catch unreachable);
    self.function_ir_builder.emitStore(next_index_register, index_storage, "i64");
    self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});

    self.function_ir_builder.emitLabel(loop_exit_label);
    environment.loop_context = previous_loop_context;

    return .{
        .exit_label = loop_exit_label,
        .register = null,
    };
}

pub fn emitDecisionConstruct(
    self: anytype,
    node: *const ast.Node,
    decision_construct: DecisionConstruct,
    label_names: DecisionLabelNames,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    var current_label = entry_label;
    var subject_register: ?Register = null;
    var subject_type_id: ?typing.TypeId = null;

    if (decision_construct.subject) |subject| {
        const subject_result = self.emitNode(subject, current_label, typed_program, environment);
        if (subject_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }
        current_label = subject_result.exit_label.?;
        subject_register = subject_result.register;
        subject_type_id = typed_program.analyzed_program.type_by_node_id.get(subject.id).?;
    }

    const result_type_id = typed_program.analyzed_program.type_by_node_id.get(node.id).?;
    const continue_label = self.function_symbol_generator.generateLabel(label_names.continue_label);
    var incoming_values = std.ArrayList(PhiIncoming){};
    defer incoming_values.deinit(self.allocator);
    var continue_reachable = false;

    const else_label = if (decision_construct.else_arm != null)
        self.function_symbol_generator.generateLabel(label_names.else_arm)
    else
        null;

    if (decision_construct.arms.len == 0 and decision_construct.else_arm != null) {
        const else_arm = decision_construct.else_arm.?;
        const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
        if (else_result.exit_label) |exit_label| {
            continue_reachable = true;
            if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
                incoming_values.append(self.allocator, .{
                    .label = exit_label,
                    .register = else_result.register.?,
                }) catch unreachable;
            }
            self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
        } else {
            return .{ .exit_label = null, .register = null };
        }
    } else {
        for (decision_construct.arms, 0..) |arm, index| {
            const arm_label = self.function_symbol_generator.generateLabel(label_names.arm);
            const is_last_arm = index + 1 == decision_construct.arms.len;
            const false_branches_to_continue = is_last_arm and
                else_label == null and
                !decision_construct.exhaustive_without_else;
            const false_label = if (!is_last_arm)
                self.function_symbol_generator.generateLabel(label_names.next)
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
                self.function_ir_builder.emitBranchInstruction(null, &.{arm_label});
            } else if (decision_construct.subject != null) {
                const pattern_result = self.emitNode(
                    arm.condition,
                    current_label,
                    typed_program,
                    environment,
                );
                if (pattern_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }
                current_label = pattern_result.exit_label.?;

                const comparison_register = self.emitLoweredBinaryOperation(
                    lowering.BinaryOperationLowerer.decisionFor(
                        .Equal,
                        subject_type_id.?,
                        typed_program.analyzed_program,
                    ),
                    subject_type_id.?,
                    subject_register.?,
                    pattern_result.register.?,
                    typed_program,
                );

                self.function_ir_builder.emitBranchInstruction(comparison_register, &.{ arm_label, false_label.? });
            } else {
                const condition_result = self.emitNode(
                    arm.condition,
                    current_label,
                    typed_program,
                    environment,
                );
                if (condition_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }
                current_label = condition_result.exit_label.?;

                self.function_ir_builder.emitBranchInstruction(condition_result.register.?, &.{ arm_label, false_label.? });
            }

            self.function_ir_builder.emitLabel(arm_label);
            const arm_result = self.emitNode(arm.body, arm_label, typed_program, environment);
            if (arm_result.exit_label) |exit_label| {
                continue_reachable = true;
                if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
                    incoming_values.append(self.allocator, .{
                        .label = exit_label,
                        .register = arm_result.register.?,
                    }) catch unreachable;
                }
                self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
            }

            if (false_label) |next_label| {
                if (!false_branches_to_continue) {
                    self.function_ir_builder.emitLabel(next_label);
                }
                current_label = next_label;
            } else {
                current_label = arm_label;
            }
        }

        if (decision_construct.else_arm) |else_arm| {
            const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
            if (else_result.exit_label) |exit_label| {
                continue_reachable = true;
                if (result_type_id != typed_program.analyzed_program.type_store.unit_type_id) {
                    incoming_values.append(self.allocator, .{
                        .label = exit_label,
                        .register = else_result.register.?,
                    }) catch unreachable;
                }
                self.function_ir_builder.emitBranchInstruction(null, &.{continue_label});
            }
        }
    }

    if (!continue_reachable) {
        return .{ .exit_label = null, .register = null };
    }

    self.function_ir_builder.emitLabel(continue_label);
    if (result_type_id == typed_program.analyzed_program.type_store.unit_type_id) {
        return .{
            .exit_label = continue_label,
            .register = null,
        };
    }
    if (incoming_values.items.len == 0) {
        return .{ .exit_label = null, .register = null };
    }
    if (incoming_values.items.len == 1) {
        return .{
            .exit_label = continue_label,
            .register = incoming_values.items[0].register,
        };
    }

    var phi_incoming_buffer = std.ArrayList(u8){};
    defer phi_incoming_buffer.deinit(self.allocator);
    for (incoming_values.items, 0..) |incoming, index| {
        if (index > 0) {
            phi_incoming_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
        }
        phi_incoming_buffer.writer(self.allocator).print(
            "[{s}, %{s}]",
            .{ incoming.register, incoming.label },
        ) catch unreachable;
    }

    const result_register = self.function_symbol_generator.generateRegister();
    const phi_instruction = std.fmt.allocPrint(
        self.allocator,
        "{s} = phi {s} {s}",
        .{
            result_register,
            typed_program.llvmIrType(result_type_id),
            phi_incoming_buffer.items,
        },
    ) catch unreachable;
    self.function_ir_builder.emitInstruction(phi_instruction);

    return .{
        .exit_label = continue_label,
        .register = result_register,
    };
}

pub fn emitLoopConstruct(
    self: anytype,
    loop_construct: LoopConstruct,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    const loop_header_label = self.function_symbol_generator.generateLabel("loop_header");
    const loop_body_label = self.function_symbol_generator.generateLabel("loop_body");
    const loop_continue_label = self.function_symbol_generator.generateLabel("loop_continue");
    const loop_exit_label = self.function_symbol_generator.generateLabel("loop_exit");
    const previous_loop_context = environment.loop_context;
    const loop_context = LoopContext{
        .continue_label = loop_continue_label,
        .leave_label = loop_exit_label,
    };
    environment.loop_context = loop_context;

    // Loop header
    self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
    self.function_ir_builder.emitLabel(loop_header_label);
    if (loop_construct.condition) |condition| {
        const condition_result = self.emitNode(
            condition,
            loop_header_label,
            typed_program,
            environment,
        );
        if (condition_result.exit_label == null) {
            environment.loop_context = previous_loop_context;
            return .{
                .exit_label = null,
                .register = null,
            };
        }
        self.function_ir_builder.emitBranchInstruction(condition_result.register.?, &.{ loop_body_label, loop_exit_label });
    } else {
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_body_label});
    }

    // Loop body
    self.function_ir_builder.emitLabel(loop_body_label);
    const body_result = self.emitBlock(loop_construct.body_block.*, loop_body_label, typed_program, environment);

    // Loop continue
    if (body_result.exit_label != null) {
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_continue_label});
    }
    self.function_ir_builder.emitLabel(loop_continue_label);
    if (loop_construct.update) |update| {
        const update_result = self.emitNode(update, loop_continue_label, typed_program, environment);
        if (update_result.exit_label != null) {
            self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
        }
    } else {
        self.function_ir_builder.emitBranchInstruction(null, &.{loop_header_label});
    }

    self.function_ir_builder.emitLabel(loop_exit_label);
    environment.loop_context = previous_loop_context;

    return .{
        .exit_label = loop_exit_label,
        .register = null,
    };
}

pub fn emitBlock(
    self: anytype,
    block: ast.Block,
    entry_label: Label,
    typed_program: *const lowering.LoweredProgram,
    environment: *Environment,
) EmissionResult {
    var current_label = entry_label;
    for (block.statements) |statement| {
        const emission_result = self.emitNode(&statement, current_label, typed_program, environment);
        if (emission_result.exit_label) |exit_label| {
            current_label = exit_label;
        } else {
            return .{
                .exit_label = null,
                .register = null,
            };
        }
    }

    // Emit the result expression if it exists
    var result_register: ?Register = null;
    if (block.result) |result_node| {
        const emission_result = self.emitNode(result_node, current_label, typed_program, environment);
        result_register = emission_result.register;
        if (emission_result.exit_label) |exit_label| {
            current_label = exit_label;
        } else {
            return .{
                .exit_label = null,
                .register = null,
            };
        }
    }

    return .{
        .exit_label = current_label,
        .register = result_register,
    };
}
