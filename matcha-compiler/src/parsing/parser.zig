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
        ExpectedLeftBrace,
        ExpectedIf,
        UnexpectedElse,
    };

    const ParseState = struct {
        current_binding_power: f64 = 0.0,
    };

    const OperatorInfo = struct {
        left_binding_power: f64,
        right_binding_power: f64,
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
            if (token.kind == .EndOfFile) {
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
        return switch (token.kind) {
            .Val => try self.parseValueDeclaration(),
            .If => try self.parseIfStatement(),
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
        if (identifierToken.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const colon_or_equal_token = self.lexer.next();
        const type_annotation: ?lexing.Token = switch (colon_or_equal_token.kind) {
            .Colon => block: {
                const next_token = self.lexer.next();
                if (next_token.kind != .Identifier) {
                    return ParserError.ExpectedTypeAnnotation;
                }

                const equalToken = self.lexer.next();
                if (equalToken.kind != .Equal) {
                    return ParserError.ExpectedEqualSign;
                }

                break :block next_token;
            },
            .Equal => null,
            else => return ParserError.ExpectedColonOrEqualSign,
        };

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
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

    fn parseIfStatement(self: *Parser) ParserError!ast.Node {
        const if_token = self.lexer.next(); // consume if token
        if (if_token.kind != .If) {
            std.debug.print("Expected if token, got token: {any}\n", .{if_token});
            return ParserError.ExpectedIf;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const then_branch = self.allocator.create(ast.Node) catch unreachable;
        var else_branch: ?ast.IfStatementElseBranch = null;

        const post_condition_token = self.lexer.peek();
        if (post_condition_token.kind == .LeftBrace) {
            const then_branch_left_brace_token = self.lexer.next();
            then_branch.* = try self.parseBlock(then_branch_left_brace_token);

            const post_then_branch_token = self.lexer.peek();
            if (post_then_branch_token.kind == .Else) {
                const else_token = self.lexer.next();

                const else_branch_left_brace_token = self.lexer.next();
                if (else_branch_left_brace_token.kind != .LeftBrace) {
                    std.debug.print(
                        "Expected left brace after else, got token: {any}\n",
                        .{else_branch_left_brace_token},
                    );
                    return ParserError.ExpectedLeftBrace;
                }
                const else_block = self.allocator.create(ast.Node) catch unreachable;
                else_block.* = try self.parseBlock(else_branch_left_brace_token);

                else_branch = .{
                    .else_token = else_token,
                    .else_block = else_block,
                };
            }
        } else {
            then_branch.* = try self.parseStatement();

            const post_then_branch_token = self.lexer.peek();
            if (post_then_branch_token.kind == .Else) {
                std.debug.print("Using else is not allowed when the then branch is a single statement without braces, got token: {any}\n", .{post_then_branch_token});
                return ParserError.UnexpectedElse;
            }
        }

        return self.createNode(.{ .IfStatement = .{
            .if_token = if_token,
            .condition = condition,
            .then_branch = then_branch,
            .else_branch = else_branch,
        } });
    }

    fn parseIfExpression(self: *Parser, if_token: lexing.Token) ParserError!ast.Node {
        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const left_brace_token = self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            std.debug.print(
                "Expected left brace after if condition in if expression, got token: {any}\n",
                .{left_brace_token},
            );
            return ParserError.ExpectedLeftBrace;
        }
        const then_block = self.allocator.create(ast.Node) catch unreachable;
        then_block.* = try self.parseBlock(left_brace_token);

        const else_token = self.lexer.next();
        if (else_token.kind != .Else) {
            std.debug.print(
                "Expected else token after then block in if expression, got token: {any}\n",
                .{else_token},
            );
            return ParserError.ExpectedIf;
        }

        const else_block = self.allocator.create(ast.Node) catch unreachable;
        const else_left_brace_token = self.lexer.next();
        if (else_left_brace_token.kind != .LeftBrace) {
            std.debug.print(
                "Expected left brace after else token in if expression, got token: {any}\n",
                .{else_left_brace_token},
            );
            return ParserError.ExpectedLeftBrace;
        }
        else_block.* = try self.parseBlock(else_left_brace_token);

        return self.createNode(.{
            .IfExpression = .{
                .if_token = if_token,
                .condition = condition,
                .then_block = then_block,
                .else_token = else_token,
                .else_block = else_block,
            },
        });
    }

    fn parseBlock(self: *Parser, leftBraceToken: lexing.Token) ParserError!ast.Node {
        var statements = std.ArrayList(ast.Node){};

        var result: ?*ast.Node = null;

        while (true) {
            const next_token = self.lexer.peek();
            std.debug.print("Parsing block, got token: {any}\n", .{next_token});
            switch (next_token.kind) {
                .RightBrace => break,
                .Val => {
                    std.debug.print("Parsing value declaration in block, got token: {any}\n", .{next_token});
                    const statement = try self.parseValueDeclaration();
                    statements.append(self.allocator, statement) catch unreachable;
                    continue;
                },
                else => {},
            }

            const expression = try self.parseExpression(.{ .current_binding_power = 0 });

            const post_expression_token = self.lexer.peek();
            std.debug.print("Post-expression token in block: {any}\n", .{post_expression_token});
            switch (post_expression_token.kind) {
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
        const expression = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolonToken = self.lexer.next();
        if (semicolonToken.kind != .Semicolon) {
            std.debug.print("Expected semicolon after expression statement, got token: {any}\n", .{semicolonToken});
            return ParserError.ExpectedSemicolon;
        }

        return expression;
    }

    pub fn parseExpression(self: *Parser, state: ParseState) ParserError!ast.Node {
        const token = self.lexer.next();
        std.debug.print("Parsing expression, got token: {any}\n", .{token});
        var left_hand_side = switch (token.kind) {
            .IntLiteral => self.createNode(.{ .IntegerLiteral = token }),
            .BooleanLiteral => self.createNode(.{ .BooleanLiteral = token }),
            .Identifier => self.createNode(.{ .Identifier = token }),
            .If => try self.parseIfExpression(token),
            .LeftParenthesis => try self.parseExpression(.{ .current_binding_power = 0 }),
            .LeftBrace => try self.parseBlock(token),
            .Minus => block: {
                const operand = self.allocator.create(ast.Node) catch unreachable;
                operand.* = try self.parseExpression(.{ .current_binding_power = 10 });

                break :block self.createNode(.{
                    .UnaryExpression = .{
                        .operator = .Negate,
                        .operator_token = token,
                        .operand = operand,
                    },
                });
            },
            else => {
                std.debug.print("Unexpected token at the beginning of expression: {any}\n", .{token});
                return ParserError.ExpectedIdentifier;
            },
        };

        if (token.kind == .LeftParenthesis) {
            const next_token = self.lexer.peek();
            if (next_token.kind != .RightParenthesis) {
                return ParserError.MissingClosingParenthesis;
            }
            _ = self.lexer.next();
        }

        while (true) {
            // Find the next operator without consuming it
            const next_token = self.lexer.peek();
            const operator = switch (next_token.kind) {
                .Plus => OperatorInfo{
                    .left_binding_power = 3.0,
                    .right_binding_power = 3.1,
                },
                .Minus => OperatorInfo{
                    .left_binding_power = 3.0,
                    .right_binding_power = 3.1,
                },
                .Asterisk => OperatorInfo{
                    .left_binding_power = 4.0,
                    .right_binding_power = 4.1,
                },
                .Slash => OperatorInfo{
                    .left_binding_power = 4.0,
                    .right_binding_power = 4.1,
                },
                .IntLiteral => return left_hand_side,
                .Identifier => return left_hand_side,
                .RightParenthesis => return left_hand_side,
                .LeftBrace => return left_hand_side,
                // In case we reach the end of the file, there is nothing more to parse so our the current
                // "left hand side" is the entire expression.
                .EndOfFile => return left_hand_side,
                .Semicolon => return left_hand_side,
                else => return left_hand_side,
            };

            if (operator.left_binding_power > state.current_binding_power) {
                // In case the next operator binds more tightly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = self.lexer.next();
                const right_hand_side = self.allocator.create(ast.Node) catch unreachable;
                right_hand_side.* = try self.parseExpression(.{ .current_binding_power = operator.right_binding_power });

                const left_hand_side_pointer = self.allocator.create(ast.Node) catch unreachable;
                left_hand_side_pointer.* = left_hand_side;

                left_hand_side = self.createNode(.{
                    .BinaryExpression = .{
                        .operator = switch (next_token.kind) {
                            .Plus => ast.BinaryOperator.Add,
                            .Minus => ast.BinaryOperator.Subtract,
                            .Asterisk => ast.BinaryOperator.Multiply,
                            .Slash => ast.BinaryOperator.Divide,
                            else => unreachable,
                        },
                        .left = left_hand_side_pointer,
                        .operator_token = next_token,
                        .right = right_hand_side,
                    },
                });
            } else {
                // In case the next operator does not bind more tightly than the current one, our current left hand side
                // expression will become the right hand side expression of the operator we last consumed.
                return left_hand_side;
            }
        }
    }
};
