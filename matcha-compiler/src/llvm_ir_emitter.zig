const std = @import("std");
const Ast = @import("abstract_syntax_tree.zig");
const Node = Ast.Node;
const Program = Ast.Program;

pub const Environment = struct {
    allocator: std.mem.Allocator,
    parent: ?*Environment,
    bindings: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) @This() {
        return .{
            .allocator = allocator,
            .parent = parent,
            .bindings = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn lookup(self: *@This(), name: []const u8) ?[]const u8 {
        if (self.bindings.get(name)) |value| {
            return value;
        }
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        return null;
    }

    pub fn insert(self: *@This(), name: []const u8, register: []const u8) !void {
        try self.bindings.put(name, register);
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
    symbolGenerator: SymbolGenerator,
    instructions: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbolGenerator = SymbolGenerator.init(allocator, ".t"),
            .instructions = .{},
        };
    }

    pub fn emitLlvmIr(self: *@This(), program: Program) []const u8 {
        var root_environment = Environment.init(self.allocator, null);
        var result_register: []const u8 = "0";
        for (program.statements) |statement| {
            result_register = self.emitNode(&statement, &root_environment) catch unreachable;
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

    fn emitNode(self: *@This(), node: *const Node, environment: *Environment) ![]const u8 {
        switch (node.*) {
            .Integer => |token| {
                return std.fmt.allocPrint(self.allocator, "{d}", .{token.type.IntLiteral}) catch unreachable;
            },
            .Identifier => |token| {
                const name = token.type.Identifier;
                if (environment.lookup(name)) |register| {
                    return register;
                } else {
                    // For now, assume 0 if not found or handle error
                    return "0";
                }
            },
            .BinaryExpression => |expr| {
                if (expr.operator.type == .Semicolon) {
                    _ = try self.emitNode(expr.left, environment);
                    return try self.emitNode(expr.right, environment);
                }

                const leftReg = try self.emitNode(expr.left, environment);
                const rightReg = try self.emitNode(expr.right, environment);
                const resultReg = self.symbolGenerator.generate();

                const op = switch (expr.operator.type) {
                    .Plus => "add",
                    .Minus => "sub",
                    .Asterisk => "mul",
                    .Slash => "sdiv",
                    else => unreachable,
                };

                const instruction = std.fmt.allocPrint(self.allocator, "{s} = {s} i64 {s}, {s}", .{ resultReg, op, leftReg, rightReg }) catch unreachable;
                try self.instructions.append(self.allocator, instruction);

                return resultReg;
            },
            .UnaryExpression => |expr| {
                const operandReg = try self.emitNode(expr.operand, environment);
                const resultReg = self.symbolGenerator.generate();

                const instruction = std.fmt.allocPrint(self.allocator, "{s} = sub i64 0, {s}", .{ resultReg, operandReg }) catch unreachable;
                try self.instructions.append(self.allocator, instruction);

                return resultReg;
            },
            .ValueDeclaration => |decl| {
                const valueReg = try self.emitNode(decl.value, environment);
                const name = decl.name.type.Identifier;
                try environment.insert(name, valueReg);
                return valueReg;
            },
            .Block => |block| {
                // Create a child environment for the block scope
                var block_environment = Environment.init(self.allocator, environment);

                // Emit all statements in the block
                for (block.statements) |statement| {
                    _ = try self.emitNode(&statement, &block_environment);
                }

                // Emit the result expression if it exists
                const resultRegister = if (block.result) |result_node|
                    try self.emitNode(result_node, &block_environment)
                else
                    "0";

                return resultRegister;
            },
            else => return "0",
        }
    }
};
