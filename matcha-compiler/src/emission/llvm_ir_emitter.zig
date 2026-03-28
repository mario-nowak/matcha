const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

const Register = []const u8;
const Instruction = []const u8;
const Label = []const u8;
const RegisterBySymbolId = std.AutoHashMap(symbols.SymbolId, Register);
const LlvmIrTypeByMatchaType = std.EnumArray(typing.Type, []const u8);

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

const llvm_ir_type_by_matcha_type = LlvmIrTypeByMatchaType.init(.{
    .Unit = "void",
    .Boolean = "i1",
    .Integer = "i64",
});

pub const Environment = struct {
    allocator: std.mem.Allocator,
    register_by_symbol_id: RegisterBySymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .register_by_symbol_id = RegisterBySymbolId.init(allocator),
        };
    }
};

pub const EmissionResult = struct {
    register: ?Register,
    exit_label: Label,
};

pub const SymbolGenerator = struct {
    allocator: std.mem.Allocator,
    register_counter: usize,
    label_counter: usize,
    register_prefix: []const u8,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) @This() {
        return .{
            .allocator = allocator,
            .register_counter = 0,
            .label_counter = 0,
            .register_prefix = prefix,
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
    lines: std.ArrayList(Line),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_generator = SymbolGenerator.init(allocator, ".t"),
            .lines = .{},
        };
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        var environment = Environment.init(self.allocator);
        var result_register: Register = "0";
        var current_label: Label = "entry";
        for (typed_program.resolved_program.program.statements) |statement| {
            const result = self.emitNode(&statement, current_label, typed_program, &environment) catch unreachable;
            current_label = result.exit_label;
            if (result.register) |register| {
                result_register = register;
            }
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

        const template =
            \\; Formatting constant
            \\@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00"
            \\; Tell LLVM C's printf exists
            \\declare i32 @printf(i8*, ...)
            \\define i32 @main() {{
            \\entry:
            \\{s}
            \\    ; get pointer to @.str
            \\    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
            \\    ; call printf with formatting string and last expression
            \\    call i32 (i8*, ...) @printf(i8* %fmtptr, i64 {s})
            \\    ret i32 0
            \\}}
        ;

        return std.fmt.allocPrint(self.allocator, template, .{ instructions_buffer.items, result_register }) catch unreachable;
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
                const register = environment.register_by_symbol_id.get(symbol_id).?;

                return .{
                    .exit_label = entry_label,
                    .register = register,
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
                    left_result.exit_label,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generateRegister();
                const operator = switch (binary_expression.operator) {
                    .Add => "add",
                    .Subtract => "sub",
                    .Multiply => "mul",
                    .Divide => "sdiv",
                };
                const operation_type = typed_program.node_type_map.get(node.id).?;
                const instruction_type = llvm_ir_type_by_matcha_type.get(operation_type);
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
                };
                try self.lines.append(self.allocator, .{ .instruction = instruction });

                return .{
                    .exit_label = operand_result.exit_label,
                    .register = result_register,
                };
            },
            .ValueDeclaration => |value_declaration| {
                const value_declaration_result = try self.emitNode(
                    value_declaration.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                try environment.register_by_symbol_id.put(symbol_id, value_declaration_result.register.?);

                return value_declaration_result;
            },
            .Block => |block| {
                var current_label = entry_label;
                for (block.statements) |statement| {
                    const emission_result = try self.emitNode(&statement, current_label, typed_program, environment);
                    current_label = emission_result.exit_label;
                }

                // Emit the result expression if it exists
                var result_register: ?Register = null;
                if (block.result) |result_node| {
                    const emission_result = try self.emitNode(result_node, current_label, typed_program, environment);
                    result_register = emission_result.register;
                    current_label = emission_result.exit_label;
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
                _ = try self.emitNode(if_statement.then_branch, then_label, typed_program, environment);
                try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });

                // "else" path
                try self.emitLabel(else_label);
                if (if_statement.else_branch) |else_branch| {
                    _ = try self.emitNode(else_branch.else_block, else_label, typed_program, environment);
                }
                try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });

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
                try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });

                // "else" path
                try self.emitLabel(else_label);
                const else_result = try self.emitNode(
                    if_expression.else_block,
                    else_label,
                    typed_program,
                    environment,
                );
                try self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction });

                // "continue" path
                try self.emitLabel(continue_label);
                const result_register = self.symbol_generator.generateRegister();
                const result_type = typed_program.node_type_map.get(node.id).?;
                const instruction_type = llvm_ir_type_by_matcha_type.get(result_type);
                const phi_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = phi {s} [{s}, %{s}], [{s}, %{s}]",
                    .{
                        result_register,
                        instruction_type,
                        then_result.register.?,
                        then_result.exit_label,
                        else_result.register.?,
                        else_result.exit_label,
                    },
                ) catch unreachable;
                try self.lines.append(self.allocator, .{ .instruction = phi_instruction });

                return .{
                    .exit_label = continue_label,
                    .register = result_register,
                };
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
};
