const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const Ast = @import("abstract_syntax_tree.zig");
const Node = Ast.Node;
const Program = Ast.Program;

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,

    pub const ParserError = error{
        MissingClosingParenthesis,
        ExpectedIdentifier,
        ExpectedEqualSign,
        ExpectedSemicolon,
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

    pub fn parse(self: *Parser) !Program {
        var statements = std.ArrayList(Node){};

        while (true) {
            const token = self.lexer.peek();
            if (token.type == .EndOfFile) {
                break;
            }

            const statement = try self.parseStatement();
            try statements.append(self.allocator, statement);
        }

        return Program{
            .statements = try statements.toOwnedSlice(self.allocator),
        };
    }

    fn parseStatement(self: *Parser) ParserError!Node {
        const token = self.lexer.peek();
        std.debug.print("Parsing statement, got token: {any}\n", .{token});
        return switch (token.type) {
            .Val => try self.parseValueDeclaration(),
            .LeftBrace => {
                const leftBrace = self.lexer.next();
                return try self.parseBlock(leftBrace);
            },
            else => try self.parseExpressionStatement(),
        };
    }

    fn parseValueDeclaration(self: *Parser) ParserError!Node {
        const valToken = self.lexer.next(); // consume 'val'

        const identifierToken = self.lexer.next();
        if (identifierToken.type != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const equalToken = self.lexer.next();
        if (equalToken.type != .Equal) {
            return ParserError.ExpectedEqualSign;
        }

        const value = self.allocator.create(Node) catch unreachable;
        value.* = try self.parseExpression(.{ .currentBindingPower = 0 });

        const semicolonToken = self.lexer.next();
        if (semicolonToken.type != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return Node{
            .ValueDeclaration = .{
                .val_token = valToken,
                .name = identifierToken,
                .type_annotation = null,
                .value = value,
            },
        };
    }

    fn parseBlock(self: *Parser, leftBraceToken: Token) ParserError!Node {
        var statements = std.ArrayList(Node){};

        var result: ?*Node = null;

        while (true) {
            const nextToken = self.lexer.peek();
            std.debug.print("Parsing block, got token: {any}\n", .{nextToken});
            switch (nextToken.type) {
                .RightBrace => break,
                .Val => {
                    std.debug.print("Parsing value declaration in block, got token: {any}\n", .{nextToken});
                    const statement = try self.parseValueDeclaration();
                    statements.append(self.allocator, statement) catch unreachable;
                    continue;
                },
                else => {},
            }

            const expression = try self.parseExpression(.{ .currentBindingPower = 0 });

            const postExpressionToken = self.lexer.peek();
            std.debug.print("Post-expression token in block: {any}\n", .{postExpressionToken});
            switch (postExpressionToken.type) {
                .Semicolon => {
                    _ = self.lexer.next(); // consume semicolon
                    statements.append(self.allocator, expression) catch unreachable;
                },
                .RightBrace => {
                    // This is the last expression in the block, we can set it as the result
                    // and break out of the loop.
                    // Note: We don't append it to statements since it's the result expression.
                    const resultNode = self.allocator.create(Node) catch unreachable;
                    resultNode.* = expression;
                    result = resultNode; // Now assign the non-optional pointer to the optional
                    break;
                },
                else => return ParserError.ExpectedSemicolon,
            }
        }

        const rightBraceToken = self.lexer.next();

        return Node{
            .Block = .{
                .left_brace = leftBraceToken,
                .statements = statements.toOwnedSlice(self.allocator) catch unreachable,
                .result = result,
                .right_brace = rightBraceToken,
            },
        };
    }

    fn parseExpressionStatement(self: *Parser) ParserError!Node {
        const expression = try self.parseExpression(.{ .currentBindingPower = 0 });

        const semicolonToken = self.lexer.next();
        if (semicolonToken.type != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return expression;
    }

    pub fn parseExpression(self: *Parser, state: ParseState) ParserError!Node {
        const token = self.lexer.next();
        std.debug.print("Parsing expression, got token: {any}\n", .{token});
        var leftHandSide = switch (token.type) {
            .IntLiteral => Node{ .Integer = token },
            .Identifier => Node{ .Identifier = token },
            .LeftParenthesis => try self.parseExpression(.{ .currentBindingPower = 0 }),
            .LeftBrace => try self.parseBlock(token),
            .Minus => block: {
                const operand = self.allocator.create(Node) catch unreachable;
                operand.* = try self.parseExpression(.{ .currentBindingPower = 10 });

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
                return ParserError.MissingClosingParenthesis;
            }
            _ = self.lexer.next();
        }

        while (true) {
            // Find the next operator without consuming it
            const nextToken = self.lexer.peek();
            const operator = switch (nextToken.type) {
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
                .LeftBrace => return leftHandSide,
                // In case we reach the end of the file, there is nothing more to parse so our the current
                // "left hand side" is the entire expression.
                .EndOfFile => return leftHandSide,
                .Semicolon => return leftHandSide,
                else => return leftHandSide,
            };

            if (operator.leftBindingPower > state.currentBindingPower) {
                // In case the next operator binds more tigthly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = self.lexer.next();
                const rightHandSide = self.allocator.create(Node) catch unreachable;
                rightHandSide.* = try self.parseExpression(.{ .currentBindingPower = operator.rightBindingPower });

                const leftHandSidePtr = self.allocator.create(Node) catch unreachable;
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
