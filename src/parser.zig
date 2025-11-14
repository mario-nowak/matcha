const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

pub const SExpression = union(enum) {
    Atom: struct {
        Token: Token,
        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("Atom({any})", .{self.Token});
        }
    },
    Operation: struct {
        Operator: Token,
        Operands: []const SExpression,
        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("Operation(Operator={any}, Operands=[\n", .{self.Operator});
            for (self.Operands, 0..) |operand, index| {
                if (index != 0) {
                    try writer.writeAll(",\n");
                }
                try operand.format(writer);
            }
            try writer.writeAll("\n])");
        }
    },

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .Atom => |atom| try atom.format(writer),
            .Operation => |operation| try operation.format(writer),
        }
    }
};

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,

    const ParseState = struct {
        currentBindingPower: f64 = 0.0,
    };

    const OperatorInfo = struct {
        leftBindingPower: f64,
        rightBindingPower: f64,
    };

    pub fn init(lexer: Lexer, allocator: std.mem.Allocator) Parser {
        return .{
            .lexer = lexer,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser, state: ParseState) !SExpression {
        std.debug.print("Parsing new expression with binding power {}\n", .{state.currentBindingPower});
        const token = self.lexer.next();
        std.debug.print("Found token: {f}\n", .{token});
        // null denotation
        var leftHandSide = switch (token.type) {
            .IntLiteral => SExpression{ .Atom = .{ .Token = token } },
            else => unreachable,
        };
        std.debug.print("Left hand side became: {f}\n", .{leftHandSide});

        while (true) {
            const nextToken = self.lexer.peek();
            std.debug.print("Next token: {f}\n", .{nextToken});
            const operator = switch (nextToken.type) {
                .Plus => OperatorInfo{
                    .leftBindingPower = 1.0,
                    .rightBindingPower = 1.1,
                },
                .Asterisk => OperatorInfo{
                    .leftBindingPower = 2.0,
                    .rightBindingPower = 2.1,
                },
                .IntLiteral => continue,
                .EndOfFile => return leftHandSide,
                else => unreachable,
            };
            std.debug.print("Next token is operator: {}\n", .{operator});

            if (operator.leftBindingPower > state.currentBindingPower) {
                _ = self.lexer.next(); // consume operator
                std.debug.print("Operator has higher higher binding power than current binding power\n", .{});
                const rightHandSide = try self.parse(.{ .currentBindingPower = operator.rightBindingPower });
                const operands = try self.allocator.alloc(SExpression, 2);
                @memcpy(operands, &[2]SExpression{ leftHandSide, rightHandSide });
                leftHandSide = .{
                    .Operation = .{
                        .Operator = nextToken,
                        .Operands = operands,
                    },
                };
            } else {
                std.debug.print("Operator has less or equal binding power than current binding power\n", .{});
                return leftHandSide;
            }
        }
    }
};
