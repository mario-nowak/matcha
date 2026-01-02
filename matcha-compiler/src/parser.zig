const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const Ast = @import("abstract_syntax_tree.zig");
const Node = Ast.Node;

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,

    pub const Error = error{
        MissingClosingParenthesis,
        ExpectedIdentifier,
        ExpectedEqualSign,
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

    pub fn parse(self: *Parser, state: ParseState) !Node {
        const token = self.lexer.next();
        var leftHandSide = switch (token.type) {
            .IntLiteral => Node{ .Integer = token },
            .Identifier => Node{ .Identifier = token },
            .LeftParenthesis => try self.parse(.{ .currentBindingPower = 0 }),
            .Val => block: {
                const identifierToken = self.lexer.next();
                if (identifierToken.type != .Identifier) {
                    return Error.ExpectedIdentifier;
                }

                const equalToken = self.lexer.next();
                if (equalToken.type != .Equal) {
                    return Error.ExpectedEqualSign;
                }

                const value = try self.allocator.create(Node);
                value.* = try self.parse(.{ .currentBindingPower = 2 });

                break :block Node{
                    .ValueDeclaration = .{
                        .val_token = token,
                        .name = identifierToken,
                        .type_annotation = null,
                        .value = value,
                    },
                };
            },
            .Minus => block: {
                const operand = try self.allocator.create(Node);
                operand.* = try self.parse(.{ .currentBindingPower = 10 });

                break :block Node{
                    .UnaryExpression = .{
                        .operator = token,
                        .operand = operand,
                    },
                };
            },
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
                .Semicolon => OperatorInfo{
                    .leftBindingPower = 1.0,
                    .rightBindingPower = 1.1,
                },
                .Plus => OperatorInfo{
                    .leftBindingPower = 3.0,
                    .rightBindingPower = 3.1,
                },
                .Minus => OperatorInfo{
                    .leftBindingPower = 3.0,
                    .rightBindingPower = 3.1,
                },
                .Asterisk => OperatorInfo{
                    .leftBindingPower = 4.0,
                    .rightBindingPower = 4.1,
                },
                .Slash => OperatorInfo{
                    .leftBindingPower = 4.0,
                    .rightBindingPower = 4.1,
                },
                .IntLiteral => return leftHandSide,
                .Identifier => return leftHandSide,
                .RightParenthesis => return leftHandSide,
                // In case we reach the end of the file, there is nothing more to parse so our the current
                // "left hand side" is the entire expression.
                .EndOfFile => return leftHandSide,
                else => return leftHandSide,
            };

            if (operator.leftBindingPower > state.currentBindingPower) {
                // In case the next operator binds more tigthly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = self.lexer.next();
                const rightHandSide = try self.allocator.create(Node);
                rightHandSide.* = try self.parse(.{ .currentBindingPower = operator.rightBindingPower });

                const leftHandSidePtr = try self.allocator.create(Node);
                leftHandSidePtr.* = leftHandSide;

                leftHandSide = Node{
                    .BinaryExpression = .{
                        .left = leftHandSidePtr,
                        .operator = nextToken,
                        .right = rightHandSide,
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
