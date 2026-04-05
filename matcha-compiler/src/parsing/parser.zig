const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");

pub const ParsedIf = union(enum) {
    statement: ast.Node,
    expression: ast.Node,
};

pub const BlockItem = union(enum) {
    statement: ast.Node,
    expression: ast.Node,
};

pub const Parser = struct {
    lexer: lexing.Lexer,
    allocator: std.mem.Allocator,
    next_node_id: ast.NodeId = 0,

    pub const ParserError = error{
        MissingClosingParenthesis,
        ExpectedOpeningParenthesis,
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
        return switch (token.kind) {
            .Val, .Var => try self.parseDeclaration(),
            .If => block: {
                const if_token = self.lexer.next();
                const if_form = try self.parseIfForm(if_token);
                break :block switch (if_form) {
                    .statement => |if_statement| if_statement,
                    .expression => |if_expression| expression_block: {
                        const next_token = self.lexer.next();
                        if (next_token.kind != .Semicolon) {
                            return ParserError.ExpectedSemicolon;
                        }
                        const expression = self.allocator.create(ast.Node) catch unreachable;
                        expression.* = if_expression;
                        break :expression_block self.createNode(.{
                            .ExpressionStatement = .{
                                .expression = expression,
                            },
                        });
                    },
                };
            },
            .Loop => try self.parseLoopStatement(),
            .Leave => {
                const leave_token = self.lexer.next();
                const semicolon = self.lexer.next();
                if (semicolon.kind != .Semicolon) {
                    return ParserError.ExpectedSemicolon;
                }
                return self.createNode(.{
                    .Leave = .{
                        .leave_token = leave_token,
                    },
                });
            },
            .Continue => {
                const continue_token = self.lexer.next();
                const semicolon = self.lexer.next();
                if (semicolon.kind != .Semicolon) {
                    return ParserError.ExpectedSemicolon;
                }
                return self.createNode(.{
                    .Continue = .{
                        .continue_token = continue_token,
                    },
                });
            },
            .LeftBrace => {
                const leftBrace = self.lexer.next();
                return try self.parseBlock(leftBrace);
            },
            .Identifier => if (self.startsAssignmentStatement())
                try self.parseAssignmentStatement()
            else
                try self.parseExpressionStatement(),
            else => try self.parseExpressionStatement(),
        };
    }

    fn startsStatementOnlyConstruct(token: lexing.Token) bool {
        return switch (token.kind) {
            .Val,
            .Var,
            .Loop,
            .Leave,
            .Continue,
            => true,
            else => false,
        };
    }

    fn parseDeclaration(self: *Parser) ParserError!ast.Node {
        const val_or_var_token = self.lexer.next(); // consume token

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
                if (equalToken.kind != .Assign) {
                    return ParserError.ExpectedEqualSign;
                }

                break :block next_token;
            },
            .Assign => null,
            else => return ParserError.ExpectedColonOrEqualSign,
        };

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .Declaration = .{
                .val_token = val_or_var_token,
                .name = identifierToken,
                .type_annotation = if (type_annotation) |typeToken| .{ .name_token = typeToken } else null,
                .value = value,
                .binding_mutability = switch (val_or_var_token.kind) {
                    .Val => ast.BindingMutability.Immutable,
                    .Var => ast.BindingMutability.Mutable,
                    else => unreachable,
                },
            },
        });
    }

    fn parseLoopStatement(self: *@This()) ParserError!ast.Node {
        const loop_token = self.lexer.next();
        if (loop_token.kind != .Loop) {
            unreachable;
        }

        const left_brace = self.lexer.next();
        if (left_brace.kind != .LeftBrace) {
            return ParserError.ExpectedLeftBrace;
        }

        var statements = std.ArrayList(ast.Node){};

        var current_token = self.lexer.peek();
        while (current_token.kind != .RightBrace) : (current_token = self.lexer.peek()) {
            statements.append(self.allocator, try self.parseStatement()) catch unreachable;
        }

        const right_brace = self.lexer.next();
        if (right_brace.kind != .RightBrace) {
            unreachable;
        }

        return self.createNode(.{
            .Loop = .{
                .loop_token = loop_token,
                .left_brace = left_brace,
                .statements = statements.toOwnedSlice(self.allocator) catch unreachable,
                .right_brace = right_brace,
            },
        });
    }

    fn parseAssignmentStatement(self: *@This()) ParserError!ast.Node {
        const identifier_token = self.lexer.next();
        if (identifier_token.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const assignment_token = self.lexer.next();
        if (assignment_token.kind != .Assign) {
            return ParserError.ExpectedEqualSign;
        }

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .Assignment = .{
                .identifier_token = identifier_token,
                .assignment_token = assignment_token,
                .value = value,
            },
        });
    }

    fn startsAssignmentStatement(self: *@This()) bool {
        var lookahead = self.lexer;
        if (lookahead.peek().kind != .Identifier) return false;

        // Advance only the copied lexer to inspect the following token.
        _ = lookahead.next();
        return lookahead.peek().kind == .Assign;
    }

    fn parseIfForm(self: *Parser, if_token: lexing.Token) ParserError!ParsedIf {
        if (if_token.kind != .If) {
            return ParserError.ExpectedIf;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const then_branch = self.allocator.create(ast.Node) catch unreachable;

        const post_condition_token = self.lexer.peek();
        if (post_condition_token.kind == .LeftBrace) {
            const then_branch_left_brace_token = self.lexer.next();
            then_branch.* = try self.parseBlock(then_branch_left_brace_token);

            const post_then_branch_token = self.lexer.peek();
            if (post_then_branch_token.kind == .Else) {
                const else_token = self.lexer.next();

                const else_branch_left_brace_token = self.lexer.next();
                if (else_branch_left_brace_token.kind != .LeftBrace) {
                    return ParserError.ExpectedLeftBrace;
                }
                const else_block = self.allocator.create(ast.Node) catch unreachable;
                else_block.* = try self.parseBlock(else_branch_left_brace_token);

                return .{
                    .expression = self.createNode(.{
                        .IfExpression = .{
                            .if_token = if_token,
                            .condition = condition,
                            .then_block = then_branch,
                            .else_token = else_token,
                            .else_block = else_block,
                        },
                    }),
                };
            } else {
                return .{
                    .statement = self.createNode(.{
                        .IfStatement = .{
                            .if_token = if_token,
                            .condition = condition,
                            .then_branch = then_branch,
                        },
                    }),
                };
            }
        } else {
            then_branch.* = try self.parseStatement();

            const post_then_branch_token = self.lexer.peek();
            if (post_then_branch_token.kind == .Else) {
                return ParserError.UnexpectedElse;
            }

            return .{
                .statement = self.createNode(.{
                    .IfStatement = .{
                        .if_token = if_token,
                        .condition = condition,
                        .then_branch = then_branch,
                    },
                }),
            };
        }
    }

    fn parseBlock(self: *Parser, leftBraceToken: lexing.Token) ParserError!ast.Node {
        var statements = std.ArrayList(ast.Node){};
        var result: ?*ast.Node = null;

        while (true) {
            const block_item = try self.parseBlockItem();
            switch (block_item) {
                .statement => |statement| {
                    statements.append(self.allocator, statement) catch unreachable;
                    const post_statement_token = self.lexer.peek();
                    if (post_statement_token.kind == .RightBrace) {
                        // Done parsing the block. It finished with a statement, so there is no result expression.
                        break;
                    }
                },
                .expression => |expression| {
                    const expression_node = self.allocator.create(ast.Node) catch unreachable;
                    expression_node.* = expression;
                    result = expression_node;
                    // Done parsing the block. It finished with an expression, so we set the result and break out of the loop.
                    break;
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

    fn parseBlockItem(self: *Parser) ParserError!BlockItem {
        const token = self.lexer.peek();
        if (Parser.startsStatementOnlyConstruct(token)) {
            const statement = try self.parseStatement();
            return .{ .statement = statement };
        }

        switch (token.kind) {
            .If => {
                const if_token = self.lexer.next(); // consume 'if'
                const if_form = try self.parseIfForm(if_token);
                return switch (if_form) {
                    .statement => |if_statement| .{ .statement = if_statement },
                    .expression => |if_expression| {
                        const post_if_expression_token = self.lexer.peek();
                        switch (post_if_expression_token.kind) {
                            .Semicolon => {
                                _ = self.lexer.next(); // consume semicolon
                                const expression_node = self.allocator.create(ast.Node) catch unreachable;
                                expression_node.* = if_expression;
                                return .{ .statement = self.createNode(.{
                                    .ExpressionStatement = .{
                                        .expression = expression_node,
                                    },
                                }) };
                            },
                            .RightBrace => return .{ .expression = if_expression },
                            else => return ParserError.ExpectedSemicolon,
                        }
                    },
                };
            },
            .Identifier => if (self.startsAssignmentStatement()) {
                const assignment_statement = try self.parseAssignmentStatement();
                return .{ .statement = assignment_statement };
            },
            else => {},
        }

        const expression = try self.parseExpression(.{ .current_binding_power = 0 });
        const post_expression_token = self.lexer.peek();
        switch (post_expression_token.kind) {
            .Semicolon => {
                _ = self.lexer.next(); // consume semicolon
                const expression_node = self.allocator.create(ast.Node) catch unreachable;
                expression_node.* = expression;
                return .{ .statement = self.createNode(.{
                    .ExpressionStatement = .{
                        .expression = expression_node,
                    },
                }) };
            },
            .RightBrace => return .{
                .expression = expression,
            },
            else => return ParserError.ExpectedSemicolon,
        }
    }

    fn parseExpressionStatement(self: *Parser) ParserError!ast.Node {
        const expression = self.allocator.create(ast.Node) catch unreachable;
        expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolonToken = self.lexer.next();
        if (semicolonToken.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .ExpressionStatement = .{
                .expression = expression,
            },
        });
    }

    pub fn parseExpression(self: *Parser, state: ParseState) ParserError!ast.Node {
        const token = self.lexer.next();
        var left_hand_side = switch (token.kind) {
            .IntLiteral => self.createNode(.{ .IntegerLiteral = token }),
            .BooleanLiteral => self.createNode(.{ .BooleanLiteral = token }),
            .Identifier => self.createNode(.{ .Identifier = token }),
            .If => if_block: {
                const if_form = try self.parseIfForm(token);
                break :if_block switch (if_form) {
                    .statement => |_| {
                        return ParserError.ExpectedIdentifier; // TODO:
                    },
                    .expression => |if_expression| if_expression,
                };
            },
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
            .Not => block: {
                const operand = self.allocator.create(ast.Node) catch unreachable;
                operand.* = try self.parseExpression(.{ .current_binding_power = 10 });

                break :block self.createNode(.{
                    .UnaryExpression = .{
                        .operator = .Not,
                        .operator_token = token,
                        .operand = operand,
                    },
                });
            },
            else => {
                std.debug.print("Expected expression starter, got: {any}\n", .{token});
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

            if (next_token.kind == .LeftParenthesis) {
                left_hand_side = try self.parseCalleeExpression(left_hand_side);
                continue;
            }

            const operator = switch (next_token.kind) {
                .Or => OperatorInfo{
                    .left_binding_power = 1.0,
                    .right_binding_power = 1.1,
                },
                .And => OperatorInfo{
                    .left_binding_power = 2.0,
                    .right_binding_power = 2.1,
                },
                .EqualEqual, .NotEqual => OperatorInfo{
                    .left_binding_power = 3.0,
                    .right_binding_power = 3.1,
                },
                .LessThan, .LessThanOrEqual, .GreaterThan, .GreaterThanOrEqual => OperatorInfo{
                    .left_binding_power = 4.0,
                    .right_binding_power = 4.1,
                },
                .Plus, .Minus => OperatorInfo{
                    .left_binding_power = 5.0,
                    .right_binding_power = 5.1,
                },
                .Asterisk, .Slash => OperatorInfo{
                    .left_binding_power = 6.0,
                    .right_binding_power = 6.1,
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
                            .EqualEqual => ast.BinaryOperator.Equal,
                            .NotEqual => ast.BinaryOperator.NotEqual,
                            .LessThan => ast.BinaryOperator.LessThan,
                            .LessThanOrEqual => ast.BinaryOperator.LessThanOrEqual,
                            .GreaterThan => ast.BinaryOperator.GreaterThan,
                            .GreaterThanOrEqual => ast.BinaryOperator.GreaterThanOrEqual,
                            .And => ast.BinaryOperator.And,
                            .Or => ast.BinaryOperator.Or,
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

    pub fn parseCalleeExpression(self: *@This(), left_hand_size: ast.Node) ParserError!ast.Node {
        const left_parenthesis = self.lexer.next();
        if (left_parenthesis.kind != .LeftParenthesis) {
            return ParserError.ExpectedOpeningParenthesis;
        }

        var next_token = self.lexer.peek();
        var arguments = std.ArrayList(ast.Node){};

        while (true) : (next_token = self.lexer.peek()) {
            if (next_token.kind == .RightParenthesis) {
                const right_parenthesis = self.lexer.next();

                const callee = self.allocator.create(ast.Node) catch unreachable;
                callee.* = left_hand_size;

                return self.createNode(.{
                    .CallExpression = .{
                        .callee = callee,
                        .left_parenthesis = left_parenthesis,
                        .arguments = arguments.toOwnedSlice(self.allocator) catch unreachable,
                        .right_parenthesis = right_parenthesis,
                    },
                });
            }

            if (next_token.kind == .Comma) {
                _ = self.lexer.next(); // consume comma
                continue;
            }

            const argument = try self.parseExpression(.{ .current_binding_power = 0.0 });
            arguments.append(self.allocator, argument) catch unreachable;
        }
    }
};
