const std = @import("std");
const SExpression = @import("parser.zig").SExpression;
const Operation = @import("parser.zig").Operation;

const Environment = std.StringHashMap([]const u8);

pub const SymbolGenerator = struct {
    counter: usize,
    prefix: []const u8,

    pub fn init(prefix: []const u8) @This() {
        return .{ .counter = 0, .prefix = prefix };
    }

    pub fn generate(self: *@This()) []const u8 {
        const symbol = std.fmt.allocPrint(std.heap.page_allocator, "%{s}_{d}", .{ self.prefix, self.counter }) catch unreachable;
        self.counter += 1;

        return symbol;
    }
};

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    environment: Environment,
    symbolGenerator: SymbolGenerator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .environment = Environment.init(allocator),
            .symbolGenerator = SymbolGenerator.init(".t"),
        };
    }

    pub fn emitLlvmIr(self: *@This(), sExpression: SExpression) []const u8 {
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
            \\    call i32 (i8*, ...) @printf(i8* %fmtptr, i32 {s})
            \\
            \\    ret i32 {s}
            \\}}
        ;
        const result = self.emitExpression(sExpression);
        return std.fmt.allocPrint(self.allocator, template, .{ result.auxiliaryEmission, result.expressionResultSymbol, result.expressionResultSymbol }) catch unreachable;
    }

    const ExpressionEmissionResult = struct {
        expressionResultSymbol: []const u8,
        auxiliaryEmission: []const u8,
    };

    fn emitExpression(self: *@This(), sExpression: SExpression) ExpressionEmissionResult {
        return switch (sExpression) {
            .Atom => |atom| .{
                .expressionResultSymbol = switch (atom.Token.type) {
                    .Identifier => |identifier| self.environment.get(identifier) orelse unreachable,
                    .IntLiteral => |intLiteral| std.fmt.allocPrint(self.allocator, "{d}", .{intLiteral}) catch unreachable,
                    else => unreachable,
                },
                .auxiliaryEmission = "",
            },
            .Operation => |operation| block: {
                const result = self.emitOperation(operation);

                break :block .{
                    .expressionResultSymbol = result.expressionResultSymbol,
                    .auxiliaryEmission = result.auxiliaryEmission,
                };
            },
        };
    }

    const OperationEmissionResult = struct {
        expressionResultSymbol: []const u8,
        auxiliaryEmission: []const u8,
    };

    fn emitOperation(self: *@This(), operation: Operation) OperationEmissionResult {
        return switch (operation.Operator.type) {
            .Semicolon => block: {
                const left = self.emitExpression(operation.Operands[0]);
                const right = self.emitExpression(operation.Operands[1]);
                const auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ left.auxiliaryEmission, right.auxiliaryEmission }) catch unreachable;

                break :block .{
                    .expressionResultSymbol = right.expressionResultSymbol,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            .Let => block: {
                const identifier = switch (operation.Operands[0]) {
                    .Atom => |atom| switch (atom.Token.type) {
                        .Identifier => |identifier| identifier,
                        else => unreachable,
                    },
                    else => unreachable,
                };
                const expression = self.emitExpression(operation.Operands[1]);
                self.environment.put(identifier, expression.expressionResultSymbol) catch unreachable;

                break :block .{ .expressionResultSymbol = expression.expressionResultSymbol, .auxiliaryEmission = expression.auxiliaryEmission };
            },
            .Plus => block: {
                const left = self.emitExpression(operation.Operands[0]);
                const right = self.emitExpression(operation.Operands[1]);

                const symbol = self.symbolGenerator.generate();

                const llvmOperation = std.fmt.allocPrint(self.allocator, "{s} = add i32 {s}, {s}", .{ symbol, left.expressionResultSymbol, right.expressionResultSymbol }) catch unreachable;
                const auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}", .{ left.auxiliaryEmission, right.auxiliaryEmission, llvmOperation }) catch unreachable;

                break :block .{
                    .expressionResultSymbol = symbol,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            .Minus => block: {
                const left = self.emitExpression(operation.Operands[0]);
                const right = self.emitExpression(operation.Operands[1]);

                const symbol = self.symbolGenerator.generate();

                const llvmOperation = std.fmt.allocPrint(self.allocator, "{s} = sub i32 {s}, {s}", .{ symbol, left.expressionResultSymbol, right.expressionResultSymbol }) catch unreachable;
                const auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}", .{ left.auxiliaryEmission, right.auxiliaryEmission, llvmOperation }) catch unreachable;

                break :block .{
                    .expressionResultSymbol = symbol,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            .Asterisk => block: {
                const left = self.emitExpression(operation.Operands[0]);
                const right = self.emitExpression(operation.Operands[1]);

                const symbol = self.symbolGenerator.generate();

                const llvmOperation = std.fmt.allocPrint(self.allocator, "{s} = mul i32 {s}, {s}", .{ symbol, left.expressionResultSymbol, right.expressionResultSymbol }) catch unreachable;
                const auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}", .{ left.auxiliaryEmission, right.auxiliaryEmission, llvmOperation }) catch unreachable;

                break :block .{
                    .expressionResultSymbol = symbol,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            else => unreachable,
        };
    }
};
