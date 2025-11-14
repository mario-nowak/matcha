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

    pub const Error = error{
        MissingClosingParenthesis,
    };

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
        const token = self.lexer.next();
        var leftHandSide = switch (token.type) {
            .IntLiteral => SExpression{ .Atom = .{ .Token = token } },
            .LeftParenthesis => try self.parse(.{ .currentBindingPower = 0 }),
            else => unreachable,
        };

        if (token.type == .LeftParenthesis) {
            const nextToken = self.lexer.peek();
            if (nextToken.type != .RightParenthesis) {
                return Error.MissingClosingParenthesis;
            }
            _ = self.lexer.next();
        }

        while (true) {
            // Find the next operator without consuming it
            const nextToken = self.lexer.peek();
            const operator = switch (nextToken.type) {
                .Plus => OperatorInfo{
                    .leftBindingPower = 1.0,
                    .rightBindingPower = 1.1,
                },
                .Minus => OperatorInfo{
                    .leftBindingPower = 1.0,
                    .rightBindingPower = 1.1,
                },
                .Asterisk => OperatorInfo{
                    .leftBindingPower = 2.0,
                    .rightBindingPower = 2.1,
                },
                .Slash => OperatorInfo{
                    .leftBindingPower = 2.0,
                    .rightBindingPower = 2.1,
                },
                .IntLiteral => continue,
                .RightParenthesis => return leftHandSide,
                // In case we reach the end of the file, there is nothing more to parse so our the current
                // "left hand side" is the entire expression.
                .EndOfFile => return leftHandSide,
                else => unreachable,
            };

            if (operator.leftBindingPower > state.currentBindingPower) {
                // In case the next operator binds more tigthly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = self.lexer.next();
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
                // In case the next operator does not bind more tightly than the current one, our current left hand side
                // expression will become the right hand side expression of the operator we last consumed.
                return leftHandSide;
            }
        }
    }
};
