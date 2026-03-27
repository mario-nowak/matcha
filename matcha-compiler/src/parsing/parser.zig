const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");

pub const Parser = struct {
    lexer: lexing.Lexer,
    allocator: std.mem.Allocator,
    next_node_id: ast.NodeId = 0,

    pub const ParserError = error{
        MissingClosingParenthesis,
        ExpectedIdentifier,
        ExpectedEqualSign,
        ExpectedSemicolon,
        ExpectedColonOrEqualSign,
        ExpectedTypeAnnotation,
    };

    const ParseState = struct {
        currentBindingPower: f64 = 0.0,
    };

    const OperatorInfo = struct {
        leftBindingPower: f64,
        rightBindingPower: f64,
    };

    pub fn init(lexer: lexing.Lexer, allocator: std.mem.Allocator) Parser {
        return .{
            .lexer = lexer,
            .allocator = allocator,
        };
    }

    fn createNode(self: *Parser, kind: ast.NodeKind) ast.Node {
        const id = self.next_node_id;
        self.next_node_id += 1;
        return .{ .id = id, .kind = kind };
    }

    pub fn parse(self: *Parser) !ast.Program {
        var statements = std.ArrayList(ast.Node){};

        while (true) {
            const token = self.lexer.peek();
            if (token.type == .EndOfFile) {
                break;
            }

            const statement = try self.parseStatement();
            try statements.append(self.allocator, statement);
        }

        return ast.Program{
            .statements = try statements.toOwnedSlice(self.allocator),
        };
    }

    fn parseStatement(self: *Parser) ParserError!ast.Node {
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

    fn parseValueDeclaration(self: *Parser) ParserError!ast.Node {
        const valToken = self.lexer.next(); // consume 'val'

        const identifierToken = self.lexer.next();
        if (identifierToken.type != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const colon_or_equal_token = self.lexer.next();
        const type_annotation: ?lexing.Token = switch (colon_or_equal_token.type) {
            .Colon => block: {
                const next_token = self.lexer.next();
                if (next_token.type != .Identifier) {
                    return ParserError.ExpectedTypeAnnotation;
                }

                const equalToken = self.lexer.next();
                if (equalToken.type != .Equal) {
                    return ParserError.ExpectedEqualSign;
                }

                break :block next_token;
            },
            .Equal => null,
            else => return ParserError.ExpectedColonOrEqualSign,
        };

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .currentBindingPower = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.type != .Semicolon) {
            std.debug.print("Expected semicolon, got token: {any}\n", .{semicolon_token});
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .ValueDeclaration = .{
                .val_token = valToken,
                .name = identifierToken,
                .type_annotation = if (type_annotation) |typeToken| .{ .name_token = typeToken } else null,
                .value = value,
            },
        });
    }

    fn parseBlock(self: *Parser, leftBraceToken: lexing.Token) ParserError!ast.Node {
        var statements = std.ArrayList(ast.Node){};

        var result: ?*ast.Node = null;

        while (true) {
            const next_token = self.lexer.peek();
            std.debug.print("Parsing block, got token: {any}\n", .{next_token});
            switch (next_token.type) {
                .RightBrace => break,
                .Val => {
                    std.debug.print("Parsing value declaration in block, got token: {any}\n", .{next_token});
                    const statement = try self.parseValueDeclaration();
                    statements.append(self.allocator, statement) catch unreachable;
                    continue;
                },
                else => {},
            }

            const expression = try self.parseExpression(.{ .currentBindingPower = 0 });

            const post_expression_token = self.lexer.peek();
            std.debug.print("Post-expression token in block: {any}\n", .{post_expression_token});
            switch (post_expression_token.type) {
                .Semicolon => {
                    _ = self.lexer.next(); // consume semicolon
                    statements.append(self.allocator, expression) catch unreachable;
                },
                .RightBrace => {
                    // This is the last expression in the block, we can set it as the result
                    // and break out of the loop.
                    // Note: We don't append it to statements since it's the result expression.
                    const resultNode = self.allocator.create(ast.Node) catch unreachable;
                    resultNode.* = expression;
                    result = resultNode; // Now assign the non-optional pointer to the optional
                    break;
                },
                else => {
                    std.debug.print("Expected semicolon or right brace after block expression, got token: {any}\n", .{post_expression_token});
                    return ParserError.ExpectedSemicolon;
                },
            }
        }

        const right_brace_token = self.lexer.next();

        return self.createNode(.{
            .Block = .{
                .left_brace = leftBraceToken,
                .statements = statements.toOwnedSlice(self.allocator) catch unreachable,
                .result = result,
                .right_brace = right_brace_token,
            },
        });
    }

    fn parseExpressionStatement(self: *Parser) ParserError!ast.Node {
        const expression = try self.parseExpression(.{ .currentBindingPower = 0 });

        const semicolonToken = self.lexer.next();
        if (semicolonToken.type != .Semicolon) {
            std.debug.print("Expected semicolon after expression statement, got token: {any}\n", .{semicolonToken});
            return ParserError.ExpectedSemicolon;
        }

        return expression;
    }

    pub fn parseExpression(self: *Parser, state: ParseState) ParserError!ast.Node {
        const token = self.lexer.next();
        std.debug.print("Parsing expression, got token: {any}\n", .{token});
        var leftHandSide = switch (token.type) {
            .IntLiteral => self.createNode(.{ .IntegerLiteral = token }),
            .BooleanLiteral => self.createNode(.{ .BooleanLiteral = token }),
            .Identifier => self.createNode(.{ .Identifier = token }),
            .LeftParenthesis => try self.parseExpression(.{ .currentBindingPower = 0 }),
            .LeftBrace => try self.parseBlock(token),
            .Minus => block: {
                const operand = self.allocator.create(ast.Node) catch unreachable;
                operand.* = try self.parseExpression(.{ .currentBindingPower = 10 });

                break :block self.createNode(.{
                    .UnaryExpression = .{
                        .operator = .Negate,
                        .operator_token = token,
                        .operand = operand,
                    },
                });
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
                const rightHandSide = self.allocator.create(ast.Node) catch unreachable;
                rightHandSide.* = try self.parseExpression(.{ .currentBindingPower = operator.rightBindingPower });

                const leftHandSidePtr = self.allocator.create(ast.Node) catch unreachable;
                leftHandSidePtr.* = leftHandSide;

                leftHandSide = self.createNode(.{
                    .BinaryExpression = .{
                        .operator = switch (nextToken.type) {
                            .Plus => ast.BinaryOperator.Add,
                            .Minus => ast.BinaryOperator.Subtract,
                            .Asterisk => ast.BinaryOperator.Multiply,
                            .Slash => ast.BinaryOperator.Divide,
                            else => unreachable,
                        },
                        .left = leftHandSidePtr,
                        .operator_token = nextToken,
                        .right = rightHandSide,
                    },
                });
            } else {
                // In case the next operator does not bind more tightly than the current one, our current left hand side
                // expression will become the right hand side expression of the operator we last consumed.
                return leftHandSide;
            }
        }
    }
};
