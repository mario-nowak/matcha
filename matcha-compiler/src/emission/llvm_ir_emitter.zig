const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

const Register = []const u8;
const Instruction = []const u8;
const RegisterBySymbolId = std.AutoHashMap(symbols.SymbolId, Register);
const LlvmIrTypeByMatchaType = std.EnumArray(typing.Type, []const u8);

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

pub const SymbolGenerator = struct {
    allocator: std.mem.Allocator,
    counter: usize,
    prefix: []const u8,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) @This() {
        return .{ .allocator = allocator, .counter = 0, .prefix = prefix };
    }

    pub fn generate(self: *@This()) []const u8 {
        const symbol = std.fmt.allocPrint(self.allocator, "%{s}_{d}", .{ self.prefix, self.counter }) catch unreachable;
        self.counter += 1;

        return symbol;
    }
};

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    symbol_generator: SymbolGenerator,
    instructions: std.ArrayList(Instruction),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_generator = SymbolGenerator.init(allocator, ".t"),
            .instructions = .{},
        };
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        var environment = Environment.init(self.allocator);
        var result_register: Register = "0";
        for (typed_program.resolved_program.program.statements) |statement| {
            result_register = self.emitNode(&statement, typed_program, &environment) catch unreachable;
        }

        var instructions_buffer = std.ArrayList(u8){};
        defer instructions_buffer.deinit(self.allocator);

        for (self.instructions.items) |instruction| {
            instructions_buffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
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
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) !Register {
        switch (node.kind) {
            .IntegerLiteral => |token| {
                return std.fmt.allocPrint(
                    self.allocator,
                    "{d}",
                    .{token.type.IntLiteral},
                ) catch unreachable;
            },
            .BooleanLiteral => |token| {
                return if (token.type.BooleanLiteral) "1" else "0";
            },
            .Identifier => {
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                const register = environment.register_by_symbol_id.get(symbol_id).?;

                return register;
            },
            .BinaryExpression => |binary_expression| {
                const left_register = try self.emitNode(
                    binary_expression.left,
                    typed_program,
                    environment,
                );
                const right_register = try self.emitNode(
                    binary_expression.right,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generate();
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
                    .{ result_register, operator, instruction_type, left_register, right_register },
                ) catch unreachable;
                try self.instructions.append(self.allocator, instruction);

                return result_register;
            },
            .UnaryExpression => |unary_expression| {
                const operand_register = try self.emitNode(
                    unary_expression.operand,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generate();
                const operation_type = typed_program.node_type_map.get(node.id).?;
                const instruction_type = llvm_ir_type_by_matcha_type.get(operation_type);
                const instruction = switch (unary_expression.operator) {
                    .Negate => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = sub {s} 0, {s}",
                        .{ result_register, instruction_type, operand_register },
                    ) catch unreachable,
                };
                try self.instructions.append(self.allocator, instruction);

                return result_register;
            },
            .ValueDeclaration => |decl| {
                const value_register = try self.emitNode(
                    decl.value,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.name_resolution_map.get(node.id).?;
                try environment.register_by_symbol_id.put(symbol_id, value_register);

                return value_register;
            },
            .Block => |block| {
                for (block.statements) |statement| {
                    _ = try self.emitNode(&statement, typed_program, environment);
                }

                // Emit the result expression if it exists
                const result_register = if (block.result) |result_node|
                    try self.emitNode(result_node, typed_program, environment)
                else
                    "0";

                return result_register;
            },
            // TODO
            .IfExpression => return "0",
        }
    }
};
