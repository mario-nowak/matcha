const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

const Register = []const u8;
const Instruction = []const u8;
const Label = []const u8;
const Storage = []const u8;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);
const LlvmIrTypeByMatchaType = std.EnumArray(typing.Type, []const u8);

const print_int_formatting_string = ".print_int_formatting_string";

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

const llvm_ir_type_by_matcha_type = LlvmIrTypeByMatchaType.init(.{
    .Unit = "void",
    .Boolean = "i1",
    .Integer = "i64",
});

const LoopContext = struct {
    continue_label: Label,
    leave_label: Label,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.storage_by_symbol_id.deinit();
    }
};

pub const EmissionResult = struct {
    register: ?Register,
    exit_label: ?Label,
};

pub const SymbolGenerator = struct {
    allocator: std.mem.Allocator,
    register_counter: usize,
    storage_counter: usize,
    label_counter: usize,
    register_prefix: []const u8,
    storage_prefix: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        register_prefix: []const u8,
        storage_prefix: []const u8,
    ) @This() {
        return .{
            .allocator = allocator,
            .register_counter = 0,
            .storage_counter = 0,
            .label_counter = 0,
            .register_prefix = register_prefix,
            .storage_prefix = storage_prefix,
        };
    }

    pub fn generateRegister(self: *@This()) Register {
        const register = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ self.register_prefix, self.register_counter },
        ) catch unreachable;
        self.register_counter += 1;

        return register;
    }

    pub fn generateStorage(self: *@This()) Storage {
        const storage = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ self.storage_prefix, self.storage_counter },
        ) catch unreachable;
        self.storage_counter += 1;

        return storage;
    }

    pub fn generateLabel(self: *@This(), label_name: []const u8) Label {
        const label = std.fmt.allocPrint(
            self.allocator,
            "label_{s}_{d}",
            .{ label_name, self.label_counter },
        ) catch unreachable;
        self.label_counter += 1;

        return label;
    }
};

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    symbol_generator: SymbolGenerator,
    storage_allocation_instructions: std.ArrayList(Instruction),
    lines: std.ArrayList(Line),
    needs_printf: bool,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_generator = SymbolGenerator.init(allocator, ".t", ".s"),
            .lines = .{},
            .storage_allocation_instructions = .{},
            .needs_printf = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        var environment = Environment.init(self.allocator, null);
        defer environment.deinit();
        var current_label: Label = "entry";
        for (typed_program.resolved_program.program.statements) |statement| {
            const result = self.emitNode(&statement, current_label, typed_program, &environment) catch unreachable;
            if (result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                break;
            }
        }

        var storage_allocation_buffer = std.ArrayList(u8){};
        defer storage_allocation_buffer.deinit(self.allocator);
        for (self.storage_allocation_instructions.items) |instruction| {
            storage_allocation_buffer.writer(self.allocator).print("   {s}\n", .{instruction}) catch unreachable;
        }

        var instructions_buffer = std.ArrayList(u8){};
        defer instructions_buffer.deinit(self.allocator);
        for (self.lines.items) |line| {
            switch (line) {
                .instruction => |instruction| {
                    instructions_buffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
                },
                .label => |label| {
                    instructions_buffer.writer(self.allocator).print("{s}:\n", .{label}) catch unreachable;
                },
            }
        }

        const prelude = if (self.needs_printf)
            \\@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c"%d\0A\00"
            \\declare i32 @printf(i8*, ...)
        else
            "";

        const template =
            \\{s}
            \\define i32 @main() {{
            \\entry:
            \\{s}
            \\{s}
            \\    ret i32 0
            \\}}
        ;

        return std.fmt.allocPrint(
            self.allocator,
            template,
            .{
                prelude,
                storage_allocation_buffer.items,
                instructions_buffer.items,
            },
        ) catch unreachable;
    }

    fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) !EmissionResult {
        switch (node.kind) {
            .IntegerLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = std.fmt.allocPrint(
                        self.allocator,
                        "{d}",
                        .{token.kind.IntLiteral},
                    ) catch unreachable,
                };
            },
            .BooleanLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = if (token.kind.BooleanLiteral) "1" else "0",
                };
            },
            .Identifier => {
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(typed_program.node_type_map.get(node.id).?);
                const register = self.symbol_generator.generateRegister();
                try self.emitLoad(register, storage, llvm_ir_type);

                return .{
                    .exit_label = entry_label,
                    .register = register,
                };
            },
            .Loop => |loop| {
                const loop_header_label = self.symbol_generator.generateLabel("loop_header");
                const loop_exit_label = self.symbol_generator.generateLabel("loop_exit");
                const previous_loop_context = environment.loop_context;
                const loop_context = LoopContext{
                    .continue_label = loop_header_label,
                    .leave_label = loop_exit_label,
                };
                environment.loop_context = loop_context;

                const branch_to_header_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{loop_header_label},
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = branch_to_header_instruction });

                try self.emitLabel(loop_header_label);
                var current_label = loop_header_label;
                var falls_through = true;
                for (loop.statements) |*statement| {
                    const result = try self.emitNode(statement, current_label, typed_program, environment);
                    if (result.exit_label) |exit_label| {
                        current_label = exit_label;
                    } else {
                        falls_through = false;
                        break;
                    }
                }

                if (falls_through) {
                    try self.lines.append(self.allocator, .{ .instruction = branch_to_header_instruction });
                }

                try self.emitLabel(loop_exit_label);

                environment.loop_context = previous_loop_context;

                return .{
                    .exit_label = loop_exit_label,
                    .register = null,
                };
            },
            .Leave => {
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{environment.loop_context.?.leave_label},
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = branch_instruction });

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .Continue => {
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{environment.loop_context.?.continue_label},
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = branch_instruction });

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .CallExpression => |call_expression| {
                switch (call_expression.callee.kind) {
                    .Identifier => |identifier| {
                        // --- Debugging ---
                        if (!std.mem.eql(u8, identifier.kind.Identifier, "printInt")) {
                            unreachable;
                        }
                    },
                    else => unreachable,
                }

                self.needs_printf = true;

                const argument_result = try self.emitNode(
                    &call_expression.arguments[0],
                    entry_label,
                    typed_program,
                    environment,
                );

                // Get pointer to the string used to format integer printing
                const integer_formatting_string_pointer = self.symbol_generator.generateRegister();
                const print_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0",
                    .{integer_formatting_string_pointer},
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = print_instruction });

                // Call C printf function with formatting string and actual value
                const call_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "call i32 (i8*, ...) @printf(i8* {s}, i64 {s})",
                    .{ integer_formatting_string_pointer, argument_result.register.? },
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = call_instruction });

                return .{
                    .exit_label = argument_result.exit_label,
                    .register = null,
                };
            },
            .BinaryExpression => |binary_expression| {
                const left_result = try self.emitNode(
                    binary_expression.left,
                    entry_label,
                    typed_program,
                    environment,
                );
                const right_result = try self.emitNode(
                    binary_expression.right,
                    left_result.exit_label.?,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generateRegister();
                const operator = switch (binary_expression.operator) {
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
                const left_operand_type = typed_program.node_type_map.get(binary_expression.left.id).?;
                const instruction_type = llvm_ir_type_by_matcha_type.get(left_operand_type);
                const instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = {s} {s} {s}, {s}",
                    .{ result_register, operator, instruction_type, left_result.register.?, right_result.register.? },
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = instruction });

                return .{
                    .exit_label = right_result.exit_label,
                    .register = result_register,
                };
            },
            .UnaryExpression => |unary_expression| {
                const operand_result = try self.emitNode(
                    unary_expression.operand,
                    entry_label,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generateRegister();
                const operation_type = typed_program.node_type_map.get(node.id).?;
                const instruction_type = llvm_ir_type_by_matcha_type.get(operation_type);
                const instruction = switch (unary_expression.operator) {
                    .Negate => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = sub {s} 0, {s}",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                    .Not => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = xor {s} {s}, 1",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                };
                try self.lines.append(self.allocator, .{ .instruction = instruction });

                return .{
                    .exit_label = operand_result.exit_label,
                    .register = result_register,
                };
            },
            .Declaration => |value_declaration| {
                const value_declaration_result = try self.emitNode(
                    value_declaration.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                const value_type = typed_program.node_type_map.get(value_declaration.value.id).?;
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(value_type);

                const storage = self.symbol_generator.generateStorage();
                try self.emitAlloca(storage, llvm_ir_type);
                try self.emitStore(value_declaration_result.register.?, storage, llvm_ir_type);

                environment.storage_by_symbol_id.put(symbol_id, storage) catch unreachable;

                return .{
                    .exit_label = value_declaration_result.exit_label,
                    .register = null,
                };
            },
            .Assignment => |assignment| {
                const value_result = try self.emitNode(
                    assignment.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const value_type = typed_program.node_type_map.get(assignment.value.id).?;
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(value_type);
                try self.emitStore(value_result.register.?, storage, llvm_ir_type);

                return .{
                    .exit_label = value_result.exit_label,
                    .register = null,
                };
            },
            .Block => |block| {
                var current_label = entry_label;
                for (block.statements) |statement| {
                    const emission_result = try self.emitNode(&statement, current_label, typed_program, environment);
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
                    const emission_result = try self.emitNode(result_node, current_label, typed_program, environment);
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
            },
            .IfStatement => |if_statement| {
                // Emit condition expression
                const condition_result = try self.emitNode(
                    if_statement.condition,
                    entry_label,
                    typed_program,
                    environment,
                );

                const then_label = self.symbol_generator.generateLabel("then");
                const continue_label = self.symbol_generator.generateLabel("continue");
                const branch_continue_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{continue_label},
                ) catch unreachable;

                // Emit branch instruction
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br i1 {s}, label %{s}, label %{s}",
                    .{ condition_result.register.?, then_label, continue_label },
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = branch_instruction });

                // "then" path
                try self.emitLabel(then_label);
                const then_result = try self.emitNode(if_statement.then_branch, then_label, typed_program, environment);
                if (then_result.exit_label) |_| {
                    try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });
                }

                try self.emitLabel(continue_label);

                return .{
                    .exit_label = continue_label,
                    .register = null,
                };
            },
            .IfExpression => |if_expression| {
                // Emit condition expression
                const condition_result = try self.emitNode(
                    if_expression.condition,
                    entry_label,
                    typed_program,
                    environment,
                );

                const then_label = self.symbol_generator.generateLabel("then");
                const else_label = self.symbol_generator.generateLabel("else");
                const continue_label = self.symbol_generator.generateLabel("continue");
                const branch_continue_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{continue_label},
                ) catch unreachable;

                // Emit branch instruction
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br i1 {s}, label %{s}, label %{s}",
                    .{ condition_result.register.?, then_label, else_label },
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = branch_instruction });

                // "then" path
                try self.emitLabel(then_label);
                const then_result = try self.emitNode(
                    if_expression.then_block,
                    then_label,
                    typed_program,
                    environment,
                );
                const then_falls_through = then_result.exit_label != null;
                if (then_falls_through) {
                    try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });
                }

                // "else" path
                try self.emitLabel(else_label);
                const else_result = try self.emitNode(
                    if_expression.else_block,
                    else_label,
                    typed_program,
                    environment,
                );
                const else_falls_through = else_result.exit_label != null;
                if (else_falls_through) {
                    try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });
                }

                if (!then_falls_through and !else_falls_through) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                // "continue" path
                try self.emitLabel(continue_label);
                const result_type = typed_program.node_type_map.get(node.id).?;
                if (result_type == .Unit) {
                    return .{
                        .exit_label = continue_label,
                        .register = null,
                    };
                } else {
                    const result_register = self.symbol_generator.generateRegister();
                    const instruction_type = llvm_ir_type_by_matcha_type.get(result_type);
                    if (then_falls_through and else_falls_through) {
                        const phi_instruction = std.fmt.allocPrint(
                            self.allocator,
                            "{s} = phi {s} [{s}, %{s}], [{s}, %{s}]",
                            .{
                                result_register,
                                instruction_type,
                                then_result.register.?,
                                then_result.exit_label.?,
                                else_result.register.?,
                                else_result.exit_label.?,
                            },
                        ) catch unreachable;
                        try self.lines.append(self.allocator, .{ .instruction = phi_instruction });

                        return .{
                            .exit_label = continue_label,
                            .register = result_register,
                        };
                    }

                    return .{
                        .exit_label = continue_label,
                        .register = if (then_falls_through) then_result.register else else_result.register,
                    };
                }
            },
            .ExpressionStatement => |expression_statement| {
                const emission_result = try self.emitNode(
                    expression_statement.expression,
                    entry_label,
                    typed_program,
                    environment,
                );

                return .{
                    .exit_label = emission_result.exit_label,
                    .register = null,
                };
            },
        }
    }

    fn emitLabel(self: *@This(), label: Label) !void {
        try self.lines.append(self.allocator, .{ .label = label });
    }

    fn emitAlloca(self: *@This(), storage: Storage, llvm_ir_type: []const u8) !void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = alloca {s}",
            .{ storage, llvm_ir_type },
        ) catch unreachable;
        try self.storage_allocation_instructions.append(self.allocator, instruction);
    }

    fn emitStore(self: *@This(), value_register: Register, storage: Storage, llvm_ir_type: []const u8) !void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, {s}* {s}",
            .{ llvm_ir_type, value_register, llvm_ir_type, storage },
        ) catch unreachable;
        try self.lines.append(self.allocator, .{ .instruction = instruction });
    }

    fn emitLoad(self: *@This(), result_register: Register, storage: Storage, llvm_ir_type: []const u8) !void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = load {s}, {s}* {s}",
            .{ result_register, llvm_ir_type, llvm_ir_type, storage },
        ) catch unreachable;
        try self.lines.append(self.allocator, .{ .instruction = instruction });
    }
};
