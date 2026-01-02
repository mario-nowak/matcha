const std = @import("std");
const Ast = @import("abstract_syntax_tree.zig");
const Node = Ast.Node;

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
    environment: std.StringHashMap([]const u8),
    instructions: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbolGenerator = SymbolGenerator.init(allocator, ".t"),
            .environment = std.StringHashMap([]const u8).init(allocator),
            .instructions = .{},
        };
    }

    pub fn emitLlvmIr(self: *@This(), node: Node) []const u8 {
        const resultRegister = self.emitNode(node) catch unreachable;

        var instructionsBuffer = std.ArrayListUnmanaged(u8){};
        defer instructionsBuffer.deinit(self.allocator);

        for (self.instructions.items) |instruction| {
            instructionsBuffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
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

        return std.fmt.allocPrint(self.allocator, template, .{ instructionsBuffer.items, resultRegister }) catch unreachable;
    }

    fn emitNode(self: *@This(), node: Node) ![]const u8 {
        switch (node) {
            .Integer => |token| {
                return std.fmt.allocPrint(self.allocator, "{d}", .{token.type.IntLiteral}) catch unreachable;
            },
            .Identifier => |token| {
                const name = token.type.Identifier;
                if (self.environment.get(name)) |register| {
                    return register;
                } else {
                    // For now, assume 0 if not found or handle error
                    return "0";
                }
            },
            .BinaryExpression => |expr| {
                if (expr.operator.type == .Semicolon) {
                    _ = try self.emitNode(expr.left.*);
                    return try self.emitNode(expr.right.*);
                }

                const leftReg = try self.emitNode(expr.left.*);
                const rightReg = try self.emitNode(expr.right.*);
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
                const operandReg = try self.emitNode(expr.operand.*);
                const resultReg = self.symbolGenerator.generate();

                const instruction = std.fmt.allocPrint(self.allocator, "{s} = sub i64 0, {s}", .{ resultReg, operandReg }) catch unreachable;
                try self.instructions.append(self.allocator, instruction);

                return resultReg;
            },
            .ValueDeclaration => |decl| {
                const valueReg = try self.emitNode(decl.value.*);
                const name = decl.name.type.Identifier;
                try self.environment.put(name, valueReg);
                return valueReg;
            },
            else => return "0",
        }
    }
};
