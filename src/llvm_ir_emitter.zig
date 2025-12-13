const std = @import("std");
const SExpression = @import("parser.zig").SExpression;
const Operation = @import("parser.zig").Operation;

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    pub fn emitLlvmIr(self: @This(), sExpression: SExpression) []const u8 {
        const template =
            \\; Formatting constant
            \\@.str = private unnamed_addr constant [4 x i8] c"%d\0A\00"
            \\; Tell LLVM C's printf exists
            \\declare i32 @printf(i8*, ...)
            \\define i32 @main() {{
            \\entry:
            \\{s}
            \\    %result = {s}
            \\    ; get pointer to @.str
            \\    %fmtptr = getelementptr inbounds [4 x i8], [4 x i8]* @.str, i64 0, i64 0
            \\    ; call printf with formatting string and last expression
            \\    call i32 (i8*, ...) @printf(i8* %fmtptr, i32 %result)
            \\
            \\    ret i32 %result
            \\}}
        ;
        const result = self.emitExpression(sExpression, null);
        return std.fmt.allocPrint(self.allocator, template, .{ result.auxiliaryEmission, result.emission }) catch unreachable;
    }

    const ExpressionEmissionResult = struct {
        emission: []const u8,
        auxiliaryEmission: []const u8,
    };

    fn emitExpression(self: @This(), sExpression: SExpression, variableName: ?[]const u8) ExpressionEmissionResult {
        return switch (sExpression) {
            .Atom => |atom| .{
                .emission = switch (atom.Token.type) {
                    .Identifier => |identifier| std.fmt.allocPrint(self.allocator, "%{s}", .{identifier}) catch unreachable,
                    .IntLiteral => |intLiteral| std.fmt.allocPrint(self.allocator, "{d}", .{intLiteral}) catch unreachable,
                    else => unreachable,
                },
                .auxiliaryEmission = "",
            },
            .Operation => |operation| block: {
                const result = self.emitOperation(operation, variableName);

                break :block .{
                    .emission = result.emission,
                    .auxiliaryEmission = result.auxiliaryEmission,
                };
            },
        };
    }

    const OperationEmissionResult = struct {
        emission: []const u8,
        auxiliaryEmission: []const u8,
    };

    fn emitOperation(self: @This(), operation: Operation, optionalVariableName: ?[]const u8) OperationEmissionResult {
        return switch (operation.Operator.type) {
            .Semicolon => block: {
                const left = self.emitExpression(operation.Operands[0], null);
                const right = self.emitExpression(operation.Operands[1], null);
                const auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ left.auxiliaryEmission, left.emission }) catch unreachable;
                const emission = std.fmt.allocPrint(self.allocator, "{s}\n{s}", .{ right.auxiliaryEmission, right.emission }) catch unreachable;

                break :block .{
                    .emission = emission,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            .Let => block: {
                const identifier = self.emitExpression(operation.Operands[0], null);
                const intermediateVariableName = std.fmt.allocPrint(self.allocator, "{s}.intermediate", .{identifier.emission}) catch unreachable;
                const expression = self.emitExpression(operation.Operands[1], intermediateVariableName);
                const emission = std.fmt.allocPrint(self.allocator, "{s} = {s}", .{ identifier.emission, expression.emission }) catch unreachable;

                break :block .{
                    .emission = emission,
                    .auxiliaryEmission = expression.auxiliaryEmission,
                };
            },
            .Plus => block: {
                const variableName = optionalVariableName orelse unreachable;
                const leftVariableName = std.fmt.allocPrint(self.allocator, "{s}.l", .{variableName}) catch unreachable;
                const rightVariableName = std.fmt.allocPrint(self.allocator, "{s}.r", .{variableName}) catch unreachable;

                const left = self.emitExpression(operation.Operands[0], leftVariableName);
                const right = self.emitExpression(operation.Operands[1], rightVariableName);

                var emission: []const u8 = undefined;
                var auxiliaryEmission: []const u8 = undefined;

                const llvmOperation = std.fmt.allocPrint(self.allocator, "{s} = add i32 {s}, {s}", .{ variableName, left.emission, right.emission }) catch unreachable;
                auxiliaryEmission = std.fmt.allocPrint(self.allocator, "{s}\n{s}\n{s}", .{ left.auxiliaryEmission, right.auxiliaryEmission, llvmOperation }) catch unreachable;
                emission = std.fmt.allocPrint(self.allocator, "{s}", .{variableName}) catch unreachable;

                break :block .{
                    .emission = emission,
                    .auxiliaryEmission = auxiliaryEmission,
                };
            },
            else => unreachable,
        };
    }
};
