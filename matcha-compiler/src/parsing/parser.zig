const std = @import("std");
const lexing = @import("lexing");
const ast = @import("ast");
const type_expressions = @import("type_expressions");

const TypeExpressionParser = @import("type_expression_parser.zig").TypeExpressionParser;

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

    pub const ParserError = @import("parse_error.zig").ParseError;

    const ParseState = struct {
        current_binding_power: f64 = 0.0,
        allow_structure_construction: bool = true,
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
            .Item => try self.parseItem(),
            .Return => try self.parseReturnStatement(),
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
            .While => try self.parseWhileStatement(),
            .For => try self.parseForStatement(),
            .LeftBrace => {
                const leftBrace = self.lexer.next();
                return try self.parseBlock(leftBrace);
            },
            .Identifier => if (self.startsAssignmentStatement())
                try self.parseAssignmentStatement(.{ .require_semicolon = true })
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
            .While,
            .For,
            .Item,
            .Return,
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
        const type_annotation: ?*type_expressions.TypeExpression = switch (colon_or_equal_token.kind) {
            .Colon => block: {
                const parsed_type_annotation = try self.parseTypeAnnotation();

                const equalToken = self.lexer.next();
                if (equalToken.kind != .Assign) {
                    return ParserError.ExpectedEqualSign;
                }

                break :block parsed_type_annotation;
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
                .type_annotation = type_annotation,
                .value = value,
                .binding_mutability = switch (val_or_var_token.kind) {
                    .Val => ast.BindingMutability.Immutable,
                    .Var => ast.BindingMutability.Mutable,
                    else => unreachable,
                },
            },
        });
    }

    fn parseItem(self: *@This()) ParserError!ast.Node {
        const item_token = self.lexer.next();
        if (item_token.kind != .Item) {
            unreachable;
        }

        const identifier_token = self.lexer.next();
        if (identifier_token.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const post_identifier_token = self.lexer.peek();
        if (post_identifier_token.kind == .LeftParenthesis) {
            return try self.parseFunctionDefinition(item_token, identifier_token);
        }
        if (post_identifier_token.kind != .Assign) {
            std.debug.print("Expected left parenthesis or equal sign after item name, got: {any}\n", .{post_identifier_token});
            return ParserError.ExpectedEqualSign;
        }
        _ = self.lexer.next(); // consume equal sign

        const post_assign_token = self.lexer.peek();
        if (post_assign_token.kind != .Structure) {
            std.debug.print("Expected 'structure' keyword after item name and equal sign, got: {any}\n", .{post_assign_token});
            return ParserError.ExpectedIdentifier;
        }

        return self.parseStructureDefinition(item_token, identifier_token);
    }

    fn parseStructureDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) ParserError!ast.Node {
        const structure = try self.parseStructure();
        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }
        return self.createNode(.{
            .ItemDefinition = .{
                .item_token = item_token,
                .identifier_token = identifier_token,
                .item = .{ .Structure = structure },
            },
        });
    }

    fn parseStructure(
        self: *@This(),
    ) ParserError!ast.Structure {
        const structure_token = self.lexer.next();
        if (structure_token.kind != .Structure) {
            unreachable;
        }

        const left_brace_token = self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            return ParserError.ExpectedLeftBrace;
        }

        var function_definitions = std.ArrayList(ast.Node){};
        var fields = std.ArrayList(ast.Field){};
        while (true) {
            const next_token = self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = self.lexer.next();
                break;
            }

            const field_name_or_item_token = self.lexer.peek();
            switch (field_name_or_item_token.kind) {
                .Identifier => {
                    const field_name_token = self.lexer.next();
                    if (field_name_token.kind != .Identifier) {
                        return ParserError.ExpectedIdentifier;
                    }

                    const colon_token = self.lexer.next();
                    if (colon_token.kind != .Colon) {
                        return ParserError.ExpectedColon;
                    }

                    const type_annotation = try self.parseTypeAnnotation();

                    fields.append(self.allocator, .{
                        .name = field_name_token,
                        .type_annotation = type_annotation,
                    }) catch unreachable;

                    const post_field_token = self.lexer.peek();
                    if (post_field_token.kind == .Semicolon) {
                        _ = self.lexer.next(); // consume semicolon and continue to next field
                    } else if (post_field_token.kind != .RightBrace) {
                        return ParserError.ExpectedSemicolon;
                    }
                },
                .Item => {
                    const item = try self.parseItem();
                    switch (item.kind) {
                        .ItemDefinition => |item_definition| {
                            switch (item_definition.item) {
                                .Function => function_definitions.append(self.allocator, item) catch unreachable,
                                else => return ParserError.ExpectedFunctionDefinitionInStructure,
                            }
                        },
                        else => unreachable,
                    }
                },
                else => return ParserError.ExpectedIdentifierOrItem,
            }
        }

        if (fields.items.len == 0) {
            std.debug.print("Structures must have at least one field\n", .{});
            return ParserError.StructureWithoutFields;
        }

        return .{
            .structure_token = structure_token,
            .fields = fields.toOwnedSlice(self.allocator) catch unreachable,
            .function_definitions = function_definitions.toOwnedSlice(self.allocator) catch unreachable,
        };
    }

    fn parseFunctionDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) ParserError!ast.Node {
        const left_parenthesis_token = self.lexer.next();
        if (left_parenthesis_token.kind != .LeftParenthesis) {
            std.debug.print("Expected left parenthesis after function name, got: {any}\n", .{left_parenthesis_token});
            return ParserError.ExpectedOpeningParenthesis;
        }

        var parameters = std.ArrayList(ast.Parameter){};
        var next_token = self.lexer.next();
        while (next_token.kind != .RightParenthesis) : (next_token = self.lexer.next()) {
            if (next_token.kind != .Identifier) {
                return ParserError.ExpectedIdentifier;
            }
            const parameter_name_token = next_token;

            const colon_token = self.lexer.next();
            if (colon_token.kind != .Colon) {
                return ParserError.ExpectedColonOrEqualSign;
            }

            const type_annotation = try self.parseTypeAnnotation();

            parameters.append(self.allocator, .{
                .name = parameter_name_token,
                .type_annotation = type_annotation,
            }) catch unreachable;

            const post_parameter_token = self.lexer.peek();
            if (post_parameter_token.kind == .Comma) {
                _ = self.lexer.next(); // consume comma and continue to next parameter
            } else if (post_parameter_token.kind != .RightParenthesis) {
                return ParserError.ExpectedCommaOrClosingParenthesis;
            }
        }

        if (next_token.kind != .RightParenthesis) {
            return ParserError.MissingClosingParenthesis;
        }

        const colon_token = self.lexer.next();
        if (colon_token.kind != .Colon) {
            return ParserError.ExpectedColon;
        }

        const return_type_annotation = try self.parseTypeAnnotation();

        const assign_token = self.lexer.next();
        if (assign_token.kind != .Assign) {
            return ParserError.ExpectedEqualSign;
        }

        const body_expression = self.allocator.create(ast.Node) catch unreachable;
        body_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .ItemDefinition = .{
                .item_token = item_token,
                .identifier_token = identifier_token,
                .item = .{
                    .Function = .{
                        .parameters = parameters.toOwnedSlice(self.allocator) catch unreachable,
                        .return_type_annotation = return_type_annotation,
                        .body_expression = body_expression,
                    },
                },
            },
        });
    }

    fn parseTypeAnnotation(self: *@This()) ParserError!*type_expressions.TypeExpression {
        var type_expression_parser = TypeExpressionParser.init(&self.lexer, self.allocator);
        return type_expression_parser.parse();
    }

    fn parseReturnStatement(self: *@This()) ParserError!ast.Node {
        const return_token = self.lexer.next();
        if (return_token.kind != .Return) {
            unreachable;
        }

        const post_return_token = self.lexer.peek();
        if (post_return_token.kind == .Semicolon) {
            _ = self.lexer.next(); // consume semicolon
            return self.createNode(.{
                .Return = .{
                    .return_token = return_token,
                    .value = null,
                },
            });
        }

        const expression = self.allocator.create(ast.Node) catch unreachable;
        expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            return ParserError.ExpectedSemicolon;
        }

        return self.createNode(.{
            .Return = .{
                .return_token = return_token,
                .value = expression,
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

        const body_block = self.allocator.create(ast.Node) catch unreachable;
        body_block.* = try self.parseBlock(left_brace);

        return self.createNode(.{
            .Loop = .{
                .loop_token = loop_token,
                .body_block = body_block,
            },
        });
    }

    fn parseWhileStatement(self: *@This()) ParserError!ast.Node {
        const while_token = self.lexer.next();
        if (while_token.kind != .While) {
            unreachable;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_construction = false,
        });

        var update: ?*ast.Node = null;
        var post_condition_token = self.lexer.peek();
        if (post_condition_token.kind == .Colon) {
            _ = self.lexer.next();
            const assignment_statement = self.allocator.create(ast.Node) catch unreachable;
            assignment_statement.* = try self.parseAssignmentStatement(.{ .require_semicolon = false });
            update = assignment_statement;
            post_condition_token = self.lexer.peek();
        }

        if (post_condition_token.kind != .LeftBrace) {
            std.debug.print("Expected left brace after while condition (and optional update), got: {any}\n", .{post_condition_token});
            return ParserError.ExpectedLeftBrace;
        }
        const left_brace_token = self.lexer.next();

        const body = self.allocator.create(ast.Node) catch unreachable;
        body.* = try self.parseBlock(left_brace_token);

        return self.createNode(.{
            .While = .{
                .while_token = while_token,
                .condition = condition,
                .update = update,
                .body_block = body,
            },
        });
    }

    fn parseForStatement(self: *@This()) ParserError!ast.Node {
        const for_token = self.lexer.next();
        if (for_token.kind != .For) {
            unreachable;
        }

        const item_name = self.lexer.next();
        if (item_name.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const in_token = self.lexer.next();
        if (in_token.kind != .In) {
            return ParserError.ExpectedIn;
        }

        const iterable = self.allocator.create(ast.Node) catch unreachable;
        iterable.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_construction = false,
        });

        const left_brace_token = self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            std.debug.print("Expected left brace after for iterable, got: {any}\n", .{left_brace_token});
            return ParserError.ExpectedLeftBrace;
        }

        const body = self.allocator.create(ast.Node) catch unreachable;
        body.* = try self.parseBlock(left_brace_token);

        return self.createNode(.{
            .ForIn = .{
                .for_token = for_token,
                .item_name = item_name,
                .in_token = in_token,
                .iterable = iterable,
                .body_block = body,
            },
        });
    }

    fn parseAssignmentStatement(self: *@This(), options: struct { require_semicolon: bool }) ParserError!ast.Node {
        const target = self.allocator.create(ast.Node) catch unreachable;
        target.* = try self.parsePlaceExpression();

        const assignment_token = self.lexer.next();
        const assignment_operator = switch (assignment_token.kind) {
            .Assign => ast.AssignmentOperator.Assign,
            .PlusAssign => ast.AssignmentOperator{ .Compound = .Add },
            .MinusAssign => ast.AssignmentOperator{ .Compound = .Subtract },
            .AsteriskAssign => ast.AssignmentOperator{ .Compound = .Multiply },
            else => null,
        };
        if (assignment_operator == null) {
            return ParserError.ExpectedEqualSign;
        }

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        if (options.require_semicolon) {
            const semicolon_token = self.lexer.next();
            if (semicolon_token.kind != .Semicolon) {
                return ParserError.ExpectedSemicolon;
            }
        }

        return self.createNode(.{
            .Assignment = .{
                .target = target,
                .operator = assignment_operator.?,
                .assignment_token = assignment_token,
                .value = value,
            },
        });
    }

    fn startsAssignmentStatement(self: *@This()) bool {
        var lookahead = self.lexer;
        if (lookahead.peek().kind != .Identifier) return false;

        _ = lookahead.next();
        while (true) {
            switch (lookahead.peek().kind) {
                .Dot => {
                    _ = lookahead.next();
                    if (lookahead.peek().kind != .Identifier) {
                        return false;
                    }
                    _ = lookahead.next();
                },
                .LeftBracket => {
                    _ = lookahead.next();
                    var bracket_depth: usize = 1;
                    while (bracket_depth > 0) {
                        const next_token = lookahead.next();
                        switch (next_token.kind) {
                            .LeftBracket => bracket_depth += 1,
                            .RightBracket => bracket_depth -= 1,
                            .EndOfFile, .Semicolon => return false,
                            else => {},
                        }
                    }
                },
                else => break,
            }
        }

        return switch (lookahead.peek().kind) {
            .Assign, .PlusAssign, .MinusAssign, .AsteriskAssign => true,
            else => false,
        };
    }

    fn parsePlaceExpression(self: *@This()) ParserError!ast.Node {
        const identifier_token = self.lexer.next();
        if (identifier_token.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        var target = self.createNode(.{ .Identifier = identifier_token });
        while (true) {
            switch (self.lexer.peek().kind) {
                .Dot => target = try self.parseMemberAccessExpression(target),
                .LeftBracket => target = try self.parseIndexAccessExpression(target),
                else => break,
            }
        }

        return target;
    }

    fn parseIfForm(self: *Parser, if_token: lexing.Token) ParserError!ParsedIf {
        if (if_token.kind != .If) {
            return ParserError.ExpectedIf;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0,
            .allow_structure_construction = false,
        });

        const then_branch_left_brace_token = self.lexer.next();
        if (then_branch_left_brace_token.kind != .LeftBrace) {
            return ParserError.ExpectedLeftBrace;
        }

        const then_branch = self.allocator.create(ast.Node) catch unreachable;

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
    }

    fn parseMatchExpression(self: *Parser, match_token: lexing.Token) ParserError!ast.Node {
        if (match_token.kind != .Match) {
            return ParserError.ExpectedMatch;
        }

        var subject: ?*ast.Node = null;
        const post_match_token = self.lexer.peek();
        if (post_match_token.kind != .LeftBrace) {
            const subject_node = self.allocator.create(ast.Node) catch unreachable;
            subject_node.* = try self.parseExpression(.{
                .current_binding_power = 0,
                .allow_structure_construction = false,
            });
            subject = subject_node;
        }

        const left_brace_token = self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            return ParserError.ExpectedLeftBrace;
        }

        var arms = std.ArrayList(ast.MatchArm){};
        var else_token: ?lexing.Token = null;
        var else_arm: ?*ast.Node = null;

        while (true) {
            const next_token = self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = self.lexer.next();
                break;
            }

            if (next_token.kind == .Else) {
                else_token = self.lexer.next();
                const arrow_token = self.lexer.next();
                if (arrow_token.kind != .FatArrow) {
                    return ParserError.ExpectedFatArrow;
                }

                const body = self.allocator.create(ast.Node) catch unreachable;
                body.* = try self.parseExpression(.{ .current_binding_power = 0 });
                else_arm = body;
            } else {
                const pattern_or_condition = self.allocator.create(ast.Node) catch unreachable;
                pattern_or_condition.* = try self.parseExpression(.{ .current_binding_power = 0 });

                const arrow_token = self.lexer.next();
                if (arrow_token.kind != .FatArrow) {
                    return ParserError.ExpectedFatArrow;
                }

                const body = self.allocator.create(ast.Node) catch unreachable;
                body.* = try self.parseExpression(.{ .current_binding_power = 0 });

                arms.append(self.allocator, .{
                    .pattern_or_condition = pattern_or_condition,
                    .body = body,
                    .fat_arrow_token = arrow_token,
                }) catch unreachable;
            }

            const separator_or_end = self.lexer.peek();
            switch (separator_or_end.kind) {
                .Comma => {
                    _ = self.lexer.next();
                },
                .RightBrace => {},
                else => return ParserError.ExpectedSemicolon,
            }
        }

        return self.createNode(.{
            .MatchExpression = .{
                .match_token = match_token,
                .subject = subject,
                .arms = arms.toOwnedSlice(self.allocator) catch unreachable,
                .else_token = else_token,
                .else_arm = else_arm,
            },
        });
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
                const assignment_statement = try self.parseAssignmentStatement(.{ .require_semicolon = true });
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
            else => {
                std.debug.print("Expected semicolon, got: {any}", .{post_expression_token.kind});
                return ParserError.ExpectedSemicolon;
            },
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
            .StringLiteral => self.createNode(.{ .StringLiteral = token }),
            .Identifier => block: {
                const post_identifier_token = self.lexer.peek();
                if (state.allow_structure_construction and post_identifier_token.kind == .LeftBrace) {
                    break :block try self.parseStructureConstruction(token);
                } else {
                    break :block self.createNode(.{ .Identifier = token });
                }
            },
            .Dot => block: {
                const post_dot_token = self.lexer.peek();
                if (state.allow_structure_construction and post_dot_token.kind == .LeftBrace) {
                    break :block try self.parseAnonymousStructureLiteral(token);
                }

                std.debug.print("Expected expression starter, got: {any}\n", .{token});
                return ParserError.ExpectedIdentifier;
            },
            .If => if_block: {
                const if_form = try self.parseIfForm(token);
                break :if_block switch (if_form) {
                    .statement => |_| {
                        return ParserError.ExpectedIdentifier; // TODO:
                    },
                    .expression => |if_expression| if_expression,
                };
            },
            .Match => try self.parseMatchExpression(token),
            .LeftBracket => try self.parseArrayLiteral(token),
            .LeftParenthesis => try self.parseExpression(.{ .current_binding_power = 0 }),
            .LeftBrace => try self.parseBlock(token),
            .Minus => block: {
                const operand = self.allocator.create(ast.Node) catch unreachable;
                operand.* = try self.parseExpression(.{
                    .current_binding_power = 10,
                    .allow_structure_construction = state.allow_structure_construction,
                });

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
                operand.* = try self.parseExpression(.{
                    .current_binding_power = 10,
                    .allow_structure_construction = state.allow_structure_construction,
                });

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

            if (next_token.kind == .Dot) {
                left_hand_side = try self.parseMemberAccessExpression(left_hand_side);
                continue;
            }

            if (next_token.kind == .LeftBracket) {
                left_hand_side = try self.parseIndexAccessExpression(left_hand_side);
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
                .FatArrow => return left_hand_side,
                // In case we reach the end of the file, there is nothing more to parse so our the current
                // "left hand side" is the entire expression.
                .EndOfFile => return left_hand_side,
                .Semicolon => return left_hand_side,
                .Comma => return left_hand_side,
                else => return left_hand_side,
            };

            if (operator.left_binding_power > state.current_binding_power) {
                // In case the next operator binds more tightly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = self.lexer.next();
                const right_hand_side = self.allocator.create(ast.Node) catch unreachable;
                right_hand_side.* = try self.parseExpression(.{
                    .current_binding_power = operator.right_binding_power,
                    .allow_structure_construction = state.allow_structure_construction,
                });

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

    fn parseStructureConstruction(self: *@This(), structure_name: lexing.Token) ParserError!ast.Node {
        const parsed_fields = try self.parseStructureConstructionFields();

        return self.createNode(.{
            .StructureConstruction = .{
                .structure_name = structure_name,
                .fields = parsed_fields.fields,
            },
        });
    }

    fn parseAnonymousStructureLiteral(self: *@This(), dot_token: lexing.Token) ParserError!ast.Node {
        const parsed_fields = try self.parseStructureConstructionFields();

        return self.createNode(.{
            .AnonymousStructureLiteral = .{
                .dot_token = dot_token,
                .left_brace = parsed_fields.left_brace_token,
                .fields = parsed_fields.fields,
            },
        });
    }

    fn parseStructureConstructionFields(self: *@This()) ParserError!struct {
        left_brace_token: lexing.Token,
        fields: []ast.StructureConstructionField,
    } {
        const left_brace_token = self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            return ParserError.ExpectedLeftBrace;
        }

        var fields = std.ArrayList(ast.StructureConstructionField){};
        while (true) {
            const next_token = self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = self.lexer.next();
                break;
            }

            const field_name_token = self.lexer.next();
            if (field_name_token.kind != .Identifier) {
                return ParserError.ExpectedIdentifier;
            }

            const assign_token = self.lexer.next();
            if (assign_token.kind != .Assign) {
                return ParserError.ExpectedAssign;
            }

            const value_expression = self.allocator.create(ast.Node) catch unreachable;
            value_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

            fields.append(self.allocator, .{
                .name = field_name_token,
                .assign_token = assign_token,
                .value = value_expression,
            }) catch unreachable;

            const post_field_token = self.lexer.peek();
            if (post_field_token.kind == .Comma) {
                _ = self.lexer.next(); // consume comma and continue to next field
            } else if (post_field_token.kind != .RightBrace) {
                return ParserError.ExpectedCommaOrRightBrace;
            }
        }

        return .{
            .left_brace_token = left_brace_token,
            .fields = fields.toOwnedSlice(self.allocator) catch unreachable,
        };
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

    fn parseArrayLiteral(self: *@This(), left_bracket_token: lexing.Token) ParserError!ast.Node {
        if (left_bracket_token.kind != .LeftBracket) {
            unreachable;
        }

        var elements = std.ArrayList(ast.Node){};
        while (true) {
            if (self.lexer.peek().kind == .RightBracket) {
                break;
            }
            const element = try self.parseExpression(.{ .current_binding_power = 0 });
            elements.append(self.allocator, element) catch unreachable;

            const post_element_token = self.lexer.peek();
            if (post_element_token.kind == .Comma) {
                _ = self.lexer.next();
                if (self.lexer.peek().kind == .RightBracket) {
                    break;
                }
                continue;
            }
            if (post_element_token.kind == .RightBracket) {
                break;
            }
            return ParserError.ExpectedCommaOrRightBracket;
        }

        const right_bracket_token = self.lexer.next();
        if (right_bracket_token.kind != .RightBracket) {
            return ParserError.ExpectedRightBracket;
        }

        return self.createNode(.{
            .ArrayLiteral = .{
                .left_bracket = left_bracket_token,
                .elements = elements.toOwnedSlice(self.allocator) catch unreachable,
                .right_bracket = right_bracket_token,
            },
        });
    }

    fn parseIndexAccessExpression(self: *@This(), left_hand_side: ast.Node) ParserError!ast.Node {
        const left_bracket_token = self.lexer.next();
        if (left_bracket_token.kind != .LeftBracket) {
            unreachable;
        }

        const index = self.allocator.create(ast.Node) catch unreachable;
        index.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const right_bracket_token = self.lexer.next();
        if (right_bracket_token.kind != .RightBracket) {
            return ParserError.ExpectedRightBracket;
        }

        const base = self.allocator.create(ast.Node) catch unreachable;
        base.* = left_hand_side;

        return self.createNode(.{
            .IndexAccess = .{
                .base = base,
                .left_bracket = left_bracket_token,
                .index = index,
                .right_bracket = right_bracket_token,
            },
        });
    }

    fn parseMemberAccessExpression(self: *@This(), left_hand_side: ast.Node) ParserError!ast.Node {
        const dot_token = self.lexer.next();
        if (dot_token.kind != .Dot) {
            unreachable;
        }

        const member_name_token = self.lexer.next();
        if (member_name_token.kind != .Identifier) {
            return ParserError.ExpectedIdentifier;
        }

        const base = self.allocator.create(ast.Node) catch unreachable;
        base.* = left_hand_side;

        return self.createNode(.{
            .MemberAccess = .{
                .base = base,
                .dot_token = dot_token,
                .member_name_token = member_name_token,
            },
        });
    }
};
