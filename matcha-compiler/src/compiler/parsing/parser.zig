const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
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
    diagnostic_store: *diagnostics.DiagnosticStore,
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

    pub fn init(lexer: lexing.Lexer, allocator: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) Parser {
        return .{
            .lexer = lexer,
            .allocator = allocator,
            .diagnostic_store = diagnostic_store,
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
            const token = try self.lexer.peek();
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
        if (self.startsItemDefinition()) {
            return try self.parseItem();
        }

        const token = try self.lexer.peek();
        return switch (token.kind) {
            .Val, .Var => try self.parseDeclaration(),
            .Return => try self.parseReturnStatement(),
            .If => try self.parseIfStatement(),
            .Loop => try self.parseLoopStatement(),
            .Leave => try self.parseLeaveStatement(),
            .Continue => try self.parseContinueStatement(),
            .While => try self.parseWhileStatement(),
            .For => try self.parseForStatement(),
            .LeftBrace => try self.parseBlockStatement(),
            .Identifier => if (self.startsAssignmentStatement())
                try self.parseAssignmentStatement(.{ .require_semicolon = true })
            else
                try self.parseExpressionStatement(),
            else => try self.parseExpressionStatement(),
        };
    }

    fn wrapExpressionStatement(self: *Parser, expression: ast.Node) ast.Node {
        const expression_node = self.allocator.create(ast.Node) catch unreachable;
        expression_node.* = expression;
        return self.createNode(.{
            .ExpressionStatement = .{
                .expression = expression_node,
            },
        });
    }

    fn parseIfStatement(self: *Parser) ParserError!ast.Node {
        const if_token = try self.lexer.next();
        const if_form = try self.parseIfForm(if_token);
        return switch (if_form) {
            .statement => |if_statement| if_statement,
            .expression => |if_expression| {
                const semicolon = try self.lexer.next();
                if (semicolon.kind != .Semicolon) {
                    try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after if expression");
                    return error.DiagnosticsEmitted;
                }
                return self.wrapExpressionStatement(if_expression);
            },
        };
    }

    fn parseLeaveStatement(self: *Parser) ParserError!ast.Node {
        const leave_token = try self.lexer.next();
        const semicolon = try self.lexer.next();
        if (semicolon.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after leave");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .Leave = .{
                .leave_token = leave_token,
            },
        });
    }

    fn parseContinueStatement(self: *Parser) ParserError!ast.Node {
        const continue_token = try self.lexer.next();
        const semicolon = try self.lexer.next();
        if (semicolon.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after continue");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .Continue = .{
                .continue_token = continue_token,
            },
        });
    }

    fn parseBlockStatement(self: *Parser) ParserError!ast.Node {
        const left_brace = try self.lexer.next();
        return self.parseBlock(left_brace);
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
            .Return,
            => true,
            else => false,
        };
    }

    fn isIdentifierNamed(token: lexing.Token, expected_name: []const u8) bool {
        return switch (token.kind) {
            .Identifier => |name| std.mem.eql(u8, name, expected_name),
            else => false,
        };
    }

    fn contextualItemToken(token: lexing.Token) ?lexing.Token {
        if (!isIdentifierNamed(token, "item")) {
            return null;
        }

        return .{
            .line = token.line,
            .column = token.column,
            .offsetInSource = token.offsetInSource,
            .lenInSource = token.lenInSource,
            .kind = .Item,
        };
    }

    fn startsItemDefinition(self: *@This()) bool {
        var lookahead = self.lexer;
        const item_token = lookahead.next() catch return false;
        if (!isIdentifierNamed(item_token, "item")) {
            return false;
        }

        if ((lookahead.peek() catch return false).kind != .Identifier) {
            return false;
        }
        _ = lookahead.next() catch return false;

        return switch ((lookahead.peek() catch return false).kind) {
            .LeftParenthesis, .Assign => true,
            else => false,
        };
    }

    fn parseDeclaration(self: *Parser) ParserError!ast.Node {
        const val_or_var_token = try self.lexer.next(); // consume token

        const identifierToken = try self.lexer.next();
        if (identifierToken.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifierToken, "expected identifier after 'val' or 'var'");
            return error.DiagnosticsEmitted;
        }

        const colon_or_equal_token = try self.lexer.next();
        const type_annotation: ?*type_expressions.TypeExpression = switch (colon_or_equal_token.kind) {
            .Colon => block: {
                const parsed_type_annotation = try self.parseTypeAnnotation();

                const equalToken = try self.lexer.next();
                if (equalToken.kind != .Assign) {
                    try self.diagnostic_store.emitErrorFromToken(equalToken, "expected '=' after type annotation in declaration");
                    return error.DiagnosticsEmitted;
                }

                break :block parsed_type_annotation;
            },
            .Assign => null,
            else => {
                try self.diagnostic_store.emitErrorFromToken(colon_or_equal_token, "expected ':' or '=' after declaration name");
                return error.DiagnosticsEmitted;
            },
        };

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after declaration");
            return error.DiagnosticsEmitted;
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
        const item_token = contextualItemToken(try self.lexer.next()) orelse unreachable;

        const identifier_token = try self.lexer.next();
        if (identifier_token.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier_token, "expected identifier after 'item'");
            return error.DiagnosticsEmitted;
        }

        const post_identifier_token = try self.lexer.peek();
        if (post_identifier_token.kind == .LeftParenthesis) {
            return try self.parseFunctionDefinition(item_token, identifier_token);
        }
        if (post_identifier_token.kind != .Assign) {
            try self.diagnostic_store.emitErrorFromToken(post_identifier_token, "expected '(' or '=' after item name");
            return error.DiagnosticsEmitted;
        }
        _ = try self.lexer.next(); // consume equal sign

        const post_assign_token = try self.lexer.peek();
        if (post_assign_token.kind != .Structure) {
            try self.diagnostic_store.emitErrorFromToken(post_assign_token, "expected 'structure' after '=' in item definition");
            return error.DiagnosticsEmitted;
        }

        return self.parseStructureDefinition(item_token, identifier_token);
    }

    fn parseStructureDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) ParserError!ast.Node {
        const structure = try self.parseStructure();
        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after structure definition");
            return error.DiagnosticsEmitted;
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
        const structure_token = try self.lexer.next();
        if (structure_token.kind != .Structure) {
            unreachable;
        }

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' after 'structure'");
            return error.DiagnosticsEmitted;
        }

        var function_definitions = std.ArrayList(ast.Node){};
        var fields = std.ArrayList(ast.Field){};
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = try self.lexer.next();
                break;
            }

            if (self.startsItemDefinition()) {
                const item = try self.parseItem();
                switch (item.kind) {
                    .ItemDefinition => |item_definition| {
                        switch (item_definition.item) {
                            .Function => function_definitions.append(self.allocator, item) catch unreachable,
                            else => {
                                try self.diagnostic_store.emitErrorFromToken(item_definition.identifier_token, "expected function definition inside structure body");
                                return error.DiagnosticsEmitted;
                            },
                        }
                    },
                    else => unreachable,
                }
                continue;
            }

            const field_name_token = try self.lexer.next();
            if (field_name_token.kind != .Identifier) {
                try self.diagnostic_store.emitErrorFromToken(field_name_token, "expected field name or item definition in structure body");
                return error.DiagnosticsEmitted;
            }

            const colon_token = try self.lexer.next();
            if (colon_token.kind != .Colon) {
                try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' after structure field name");
                return error.DiagnosticsEmitted;
            }

            const type_annotation = try self.parseTypeAnnotation();

            fields.append(self.allocator, .{
                .name = field_name_token,
                .type_annotation = type_annotation,
            }) catch unreachable;

            const post_field_token = try self.lexer.peek();
            if (post_field_token.kind == .Semicolon) {
                _ = try self.lexer.next(); // consume semicolon and continue to next field
            } else if (post_field_token.kind != .RightBrace) {
                try self.diagnostic_store.emitErrorFromToken(post_field_token, "expected ';' or '}' after structure field");
                return error.DiagnosticsEmitted;
            }
        }

        if (fields.items.len == 0) {
            try self.diagnostic_store.emitErrorFromToken(structure_token, "structure must declare at least one field");
            return error.DiagnosticsEmitted;
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
        const left_parenthesis_token = try self.lexer.next();
        if (left_parenthesis_token.kind != .LeftParenthesis) {
            try self.diagnostic_store.emitErrorFromToken(left_parenthesis_token, "expected '(' after function name");
            return error.DiagnosticsEmitted;
        }

        var parameters = std.ArrayList(ast.Parameter){};
        var next_token = try self.lexer.next();
        while (next_token.kind != .RightParenthesis) : (next_token = try self.lexer.next()) {
            if (next_token.kind != .Identifier) {
                try self.diagnostic_store.emitErrorFromToken(next_token, "expected parameter name");
                return error.DiagnosticsEmitted;
            }
            const parameter_name_token = next_token;

            const colon_token = try self.lexer.next();
            if (colon_token.kind != .Colon) {
                try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' after parameter name");
                return error.DiagnosticsEmitted;
            }

            const type_annotation = try self.parseTypeAnnotation();

            parameters.append(self.allocator, .{
                .name = parameter_name_token,
                .type_annotation = type_annotation,
            }) catch unreachable;

            const post_parameter_token = try self.lexer.peek();
            if (post_parameter_token.kind == .Comma) {
                _ = try self.lexer.next(); // consume comma and continue to next parameter
            } else if (post_parameter_token.kind != .RightParenthesis) {
                try self.diagnostic_store.emitErrorFromToken(post_parameter_token, "expected ',' or ')' after parameter");
                return error.DiagnosticsEmitted;
            }
        }

        if (next_token.kind != .RightParenthesis) {
            try self.diagnostic_store.emitErrorFromToken(next_token, "expected ')' after parameter list");
            return error.DiagnosticsEmitted;
        }

        const colon_token = try self.lexer.next();
        if (colon_token.kind != .Colon) {
            try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' before function return type");
            return error.DiagnosticsEmitted;
        }

        const return_type_annotation = try self.parseTypeAnnotation();

        const assign_token = try self.lexer.next();
        if (assign_token.kind != .Assign) {
            try self.diagnostic_store.emitErrorFromToken(assign_token, "expected '=' before function body");
            return error.DiagnosticsEmitted;
        }

        const body_expression = self.allocator.create(ast.Node) catch unreachable;
        body_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after function definition");
            return error.DiagnosticsEmitted;
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
        var type_expression_parser = TypeExpressionParser.init(&self.lexer, self.allocator, self.diagnostic_store);
        return type_expression_parser.parse();
    }

    fn parseReturnStatement(self: *@This()) ParserError!ast.Node {
        const return_token = try self.lexer.next();
        if (return_token.kind != .Return) {
            unreachable;
        }

        const post_return_token = try self.lexer.peek();
        if (post_return_token.kind == .Semicolon) {
            _ = try self.lexer.next(); // consume semicolon
            return self.createNode(.{
                .Return = .{
                    .return_token = return_token,
                    .value = null,
                },
            });
        }

        const expression = self.allocator.create(ast.Node) catch unreachable;
        expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after return value");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .Return = .{
                .return_token = return_token,
                .value = expression,
            },
        });
    }

    fn parseLoopStatement(self: *@This()) ParserError!ast.Node {
        const loop_token = try self.lexer.next();
        if (loop_token.kind != .Loop) {
            unreachable;
        }

        const left_brace = try self.lexer.next();
        if (left_brace.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace, "expected '{' after 'loop'");
            return error.DiagnosticsEmitted;
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
        const while_token = try self.lexer.next();
        if (while_token.kind != .While) {
            unreachable;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_construction = false,
        });

        var update: ?*ast.Node = null;
        var post_condition_token = try self.lexer.peek();
        if (post_condition_token.kind == .Colon) {
            _ = try self.lexer.next();
            const assignment_statement = self.allocator.create(ast.Node) catch unreachable;
            assignment_statement.* = try self.parseAssignmentStatement(.{ .require_semicolon = false });
            update = assignment_statement;
            post_condition_token = try self.lexer.peek();
        }

        if (post_condition_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(post_condition_token, "expected '{' after while condition");
            return error.DiagnosticsEmitted;
        }
        const left_brace_token = try self.lexer.next();

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
        const for_token = try self.lexer.next();
        if (for_token.kind != .For) {
            unreachable;
        }

        const item_name = try self.lexer.next();
        if (item_name.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(item_name, "expected loop variable name after 'for'");
            return error.DiagnosticsEmitted;
        }

        const in_token = try self.lexer.next();
        if (in_token.kind != .In) {
            try self.diagnostic_store.emitErrorFromToken(in_token, "expected 'in' after loop variable");
            return error.DiagnosticsEmitted;
        }

        const iterable = self.allocator.create(ast.Node) catch unreachable;
        iterable.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_construction = false,
        });

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' after for iterable");
            return error.DiagnosticsEmitted;
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

        const assignment_token = try self.lexer.next();
        const assignment_operator = switch (assignment_token.kind) {
            .Assign => ast.AssignmentOperator.Assign,
            .PlusAssign => ast.AssignmentOperator{ .Compound = .Add },
            .MinusAssign => ast.AssignmentOperator{ .Compound = .Subtract },
            .AsteriskAssign => ast.AssignmentOperator{ .Compound = .Multiply },
            else => null,
        };
        if (assignment_operator == null) {
            try self.diagnostic_store.emitErrorFromToken(assignment_token, "expected assignment operator");
            return error.DiagnosticsEmitted;
        }

        const value = self.allocator.create(ast.Node) catch unreachable;
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        if (options.require_semicolon) {
            const semicolon_token = try self.lexer.next();
            if (semicolon_token.kind != .Semicolon) {
                try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after assignment");
                return error.DiagnosticsEmitted;
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
        if ((lookahead.peek() catch return false).kind != .Identifier) return false;

        _ = lookahead.next() catch return false;
        while (true) {
            switch ((lookahead.peek() catch return false).kind) {
                .Dot => {
                    _ = lookahead.next() catch return false;
                    if ((lookahead.peek() catch return false).kind != .Identifier) {
                        return false;
                    }
                    _ = lookahead.next() catch return false;
                },
                .LeftBracket => {
                    _ = lookahead.next() catch return false;
                    var bracket_depth: usize = 1;
                    while (bracket_depth > 0) {
                        const next_token = lookahead.next() catch return false;
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

        return switch ((lookahead.peek() catch return false).kind) {
            .Assign, .PlusAssign, .MinusAssign, .AsteriskAssign => true,
            else => false,
        };
    }

    fn parsePlaceExpression(self: *@This()) ParserError!ast.Node {
        const identifier_token = try self.lexer.next();
        if (identifier_token.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier_token, "expected identifier");
            return error.DiagnosticsEmitted;
        }

        var target = self.createNode(.{ .Identifier = identifier_token });
        while (true) {
            switch ((try self.lexer.peek()).kind) {
                .Dot => target = try self.parseMemberAccessExpression(target),
                .LeftBracket => target = try self.parseIndexAccessExpression(target),
                else => break,
            }
        }

        return target;
    }

    fn parseIfForm(self: *Parser, if_token: lexing.Token) ParserError!ParsedIf {
        if (if_token.kind != .If) {
            try self.diagnostic_store.emitErrorFromToken(if_token, "expected 'if'");
            return error.DiagnosticsEmitted;
        }

        const condition = self.allocator.create(ast.Node) catch unreachable;
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0,
            .allow_structure_construction = false,
        });

        const then_branch_left_brace_token = try self.lexer.next();
        if (then_branch_left_brace_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(then_branch_left_brace_token, "expected '{' after if condition");
            return error.DiagnosticsEmitted;
        }

        const then_branch = self.allocator.create(ast.Node) catch unreachable;

        then_branch.* = try self.parseBlock(then_branch_left_brace_token);

        const post_then_branch_token = try self.lexer.peek();
        if (post_then_branch_token.kind == .Else) {
            const else_token = try self.lexer.next();

            const else_branch_left_brace_token = try self.lexer.next();
            if (else_branch_left_brace_token.kind != .LeftBrace) {
                try self.diagnostic_store.emitErrorFromToken(else_branch_left_brace_token, "expected '{' after 'else'");
                return error.DiagnosticsEmitted;
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
            try self.diagnostic_store.emitErrorFromToken(match_token, "expected 'match'");
            return error.DiagnosticsEmitted;
        }

        var subject: ?*ast.Node = null;
        const post_match_token = try self.lexer.peek();
        if (post_match_token.kind != .LeftBrace) {
            const subject_node = self.allocator.create(ast.Node) catch unreachable;
            subject_node.* = try self.parseExpression(.{
                .current_binding_power = 0,
                .allow_structure_construction = false,
            });
            subject = subject_node;
        }

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' to start match body");
            return error.DiagnosticsEmitted;
        }

        var arms = std.ArrayList(ast.MatchArm){};
        var else_token: ?lexing.Token = null;
        var else_arm: ?*ast.Node = null;

        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = try self.lexer.next();
                break;
            }

            if (next_token.kind == .Else) {
                else_token = try self.lexer.next();
                const arrow_token = try self.lexer.next();
                if (arrow_token.kind != .FatArrow) {
                    try self.diagnostic_store.emitErrorFromToken(arrow_token, "expected '=>' after 'else' in match expression");
                    return error.DiagnosticsEmitted;
                }

                const body = self.allocator.create(ast.Node) catch unreachable;
                body.* = try self.parseExpression(.{ .current_binding_power = 0 });
                else_arm = body;
            } else {
                const pattern_or_condition = self.allocator.create(ast.Node) catch unreachable;
                pattern_or_condition.* = try self.parseExpression(.{ .current_binding_power = 0 });

                const arrow_token = try self.lexer.next();
                if (arrow_token.kind != .FatArrow) {
                    try self.diagnostic_store.emitErrorFromToken(arrow_token, "expected '=>' in match arm");
                    return error.DiagnosticsEmitted;
                }

                const body = self.allocator.create(ast.Node) catch unreachable;
                body.* = try self.parseExpression(.{ .current_binding_power = 0 });

                arms.append(self.allocator, .{
                    .pattern_or_condition = pattern_or_condition,
                    .body = body,
                    .fat_arrow_token = arrow_token,
                }) catch unreachable;
            }

            const separator_or_end = try self.lexer.peek();
            switch (separator_or_end.kind) {
                .Comma => {
                    _ = try self.lexer.next();
                },
                .RightBrace => {},
                else => {
                    try self.diagnostic_store.emitErrorFromToken(separator_or_end, "expected ',' or '}' after match arm");
                    return error.DiagnosticsEmitted;
                },
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
                    const post_statement_token = try self.lexer.peek();
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

        const right_brace_token = try self.lexer.next();

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
        const token = try self.lexer.peek();
        if (Parser.startsStatementOnlyConstruct(token)) {
            const statement = try self.parseStatement();
            return .{ .statement = statement };
        }

        switch (token.kind) {
            .If => {
                return try self.parseIfBlockItem();
            },
            .Identifier => if (self.startsAssignmentStatement()) {
                const assignment_statement = try self.parseAssignmentStatement(.{ .require_semicolon = true });
                return .{ .statement = assignment_statement };
            },
            else => {},
        }

        const expression = try self.parseExpression(.{ .current_binding_power = 0 });
        const post_expression_token = try self.lexer.peek();
        switch (post_expression_token.kind) {
            .Semicolon => {
                _ = try self.lexer.next(); // consume semicolon
                return .{ .statement = self.wrapExpressionStatement(expression) };
            },
            .RightBrace => return .{
                .expression = expression,
            },
            else => {
                try self.diagnostic_store.emitErrorFromToken(post_expression_token, "expected ';' after expression");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseIfBlockItem(self: *Parser) ParserError!BlockItem {
        const if_token = try self.lexer.next();
        const if_form = try self.parseIfForm(if_token);
        return switch (if_form) {
            .statement => |if_statement| .{ .statement = if_statement },
            .expression => |if_expression| {
                const post_if_expression_token = try self.lexer.peek();
                switch (post_if_expression_token.kind) {
                    .Semicolon => {
                        _ = try self.lexer.next();
                        return .{ .statement = self.wrapExpressionStatement(if_expression) };
                    },
                    .RightBrace => return .{ .expression = if_expression },
                    else => {
                        try self.diagnostic_store.emitErrorFromToken(post_if_expression_token, "expected ';' after if expression");
                        return error.DiagnosticsEmitted;
                    },
                }
            },
        };
    }

    fn parseExpressionStatement(self: *Parser) ParserError!ast.Node {
        const expression = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolonToken = try self.lexer.next();
        if (semicolonToken.kind != .Semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolonToken, "expected ';' after expression");
            return error.DiagnosticsEmitted;
        }

        return self.wrapExpressionStatement(expression);
    }

    pub fn parseExpression(self: *Parser, state: ParseState) ParserError!ast.Node {
        const token = try self.lexer.next();
        var left_hand_side = try self.parsePrefixExpression(token, state);

        if (token.kind == .LeftParenthesis) {
            const next_token = try self.lexer.peek();
            if (next_token.kind != .RightParenthesis) {
                try self.diagnostic_store.emitErrorFromToken(next_token, "expected ')' to close grouped expression");
                return error.DiagnosticsEmitted;
            }
            _ = try self.lexer.next();
        }

        while (true) {
            // Find the next operator without consuming it
            const next_token = try self.lexer.peek();

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

            const operator = getInfixOperatorInfo(next_token.kind) orelse {
                // In case we reach the end of the file, there is nothing more to parse so our current
                // "left hand side" is the entire expression.
                return left_hand_side;
            };

            if (operator.left_binding_power > state.current_binding_power) {
                // In case the next operator binds more tightly than the current one, we need to parse it recursively
                // first before we can incorporate it into the current expression.
                // Therefore, we consume the currently peeked operator and parse whatever is to the right hand side of
                // our current operator.
                _ = try self.lexer.next();
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

    fn getInfixOperatorInfo(kind: lexing.TokenKind) ?OperatorInfo {
        return switch (kind) {
            .Or => .{
                .left_binding_power = 1.0,
                .right_binding_power = 1.1,
            },
            .And => .{
                .left_binding_power = 2.0,
                .right_binding_power = 2.1,
            },
            .EqualEqual, .NotEqual => .{
                .left_binding_power = 3.0,
                .right_binding_power = 3.1,
            },
            .LessThan, .LessThanOrEqual, .GreaterThan, .GreaterThanOrEqual => .{
                .left_binding_power = 4.0,
                .right_binding_power = 4.1,
            },
            .Plus, .Minus => .{
                .left_binding_power = 5.0,
                .right_binding_power = 5.1,
            },
            .Asterisk, .Slash => .{
                .left_binding_power = 6.0,
                .right_binding_power = 6.1,
            },
            else => null,
        };
    }

    fn getPrefixOperatorBindingPower(kind: lexing.TokenKind) ?f64 {
        return switch (kind) {
            .Minus, .Not => 7.0,
            else => null,
        };
    }

    fn parsePrefixExpression(self: *Parser, token: lexing.Token, state: ParseState) ParserError!ast.Node {
        return switch (token.kind) {
            .IntLiteral => self.createNode(.{ .IntegerLiteral = token }),
            .BooleanLiteral => self.createNode(.{ .BooleanLiteral = token }),
            .StringLiteral => self.createNode(.{ .StringLiteral = token }),
            .Identifier => try self.parseIdentifierExpression(token, state),
            .Dot => try self.parseDotExpression(token, state),
            .If => try self.parseIfExpression(token),
            .Match => try self.parseMatchExpression(token),
            .LeftBracket => try self.parseArrayLiteral(token),
            .LeftParenthesis => try self.parseExpression(.{ .current_binding_power = 0 }),
            .LeftBrace => try self.parseBlock(token),
            .Else => {
                try self.diagnostic_store.emitErrorFromToken(token, "unexpected 'else'");
                return error.DiagnosticsEmitted;
            },
            .Minus => try self.parseUnaryExpression(token, .Negate, state),
            .Not => try self.parseUnaryExpression(token, .Not, state),
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected expression");
                return error.DiagnosticsEmitted;
            },
        };
    }

    fn parseIdentifierExpression(self: *Parser, token: lexing.Token, state: ParseState) ParserError!ast.Node {
        const post_identifier_token = try self.lexer.peek();
        if (state.allow_structure_construction and post_identifier_token.kind == .LeftBrace) {
            return self.parseStructureConstruction(token);
        }
        return self.createNode(.{ .Identifier = token });
    }

    fn parseDotExpression(self: *Parser, token: lexing.Token, state: ParseState) ParserError!ast.Node {
        const post_dot_token = try self.lexer.peek();
        if (state.allow_structure_construction and post_dot_token.kind == .LeftBrace) {
            return self.parseAnonymousStructureLiteral(token);
        }

        try self.diagnostic_store.emitErrorFromToken(token, "expected '{' after '.' in anonymous structure literal");

        return error.DiagnosticsEmitted;
    }

    fn parseIfExpression(self: *Parser, token: lexing.Token) ParserError!ast.Node {
        const if_form = try self.parseIfForm(token);
        return switch (if_form) {
            .statement => |_| {
                try self.diagnostic_store.emitErrorFromToken(token, "expected 'else' branch in if expression");
                return error.DiagnosticsEmitted;
            },
            .expression => |if_expression| if_expression,
        };
    }

    fn parseUnaryExpression(
        self: *Parser,
        token: lexing.Token,
        operator: ast.UnaryOperator,
        state: ParseState,
    ) ParserError!ast.Node {
        const prefix_binding_power = getPrefixOperatorBindingPower(token.kind) orelse unreachable;

        const operand = self.allocator.create(ast.Node) catch unreachable;
        operand.* = try self.parseExpression(.{
            .current_binding_power = prefix_binding_power,
            .allow_structure_construction = state.allow_structure_construction,
        });

        return self.createNode(.{
            .UnaryExpression = .{
                .operator = operator,
                .operator_token = token,
                .operand = operand,
            },
        });
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
        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .LeftBrace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' to start structure construction");
            return error.DiagnosticsEmitted;
        }

        var fields = std.ArrayList(ast.StructureConstructionField){};
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .RightBrace) {
                _ = try self.lexer.next();
                break;
            }

            const field_name_token = try self.lexer.next();
            if (field_name_token.kind != .Identifier) {
                try self.diagnostic_store.emitErrorFromToken(field_name_token, "expected field name in structure construction");
                return error.DiagnosticsEmitted;
            }

            const assign_token = try self.lexer.next();
            if (assign_token.kind != .Assign) {
                try self.diagnostic_store.emitErrorFromToken(assign_token, "expected '=' after field name in structure construction");
                return error.DiagnosticsEmitted;
            }

            const value_expression = self.allocator.create(ast.Node) catch unreachable;
            value_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

            fields.append(self.allocator, .{
                .name = field_name_token,
                .assign_token = assign_token,
                .value = value_expression,
            }) catch unreachable;

            const post_field_token = try self.lexer.peek();
            if (post_field_token.kind == .Comma) {
                _ = try self.lexer.next(); // consume comma and continue to next field
            } else if (post_field_token.kind != .RightBrace) {
                try self.diagnostic_store.emitErrorFromToken(post_field_token, "expected ',' or '}' after structure field");
                return error.DiagnosticsEmitted;
            }
        }

        return .{
            .left_brace_token = left_brace_token,
            .fields = fields.toOwnedSlice(self.allocator) catch unreachable,
        };
    }

    pub fn parseCalleeExpression(self: *@This(), left_hand_size: ast.Node) ParserError!ast.Node {
        const left_parenthesis = try self.lexer.next();
        if (left_parenthesis.kind != .LeftParenthesis) {
            try self.diagnostic_store.emitErrorFromToken(left_parenthesis, "expected '(' to start argument list");
            return error.DiagnosticsEmitted;
        }

        var next_token = try self.lexer.peek();
        var arguments = std.ArrayList(ast.Node){};

        while (true) : (next_token = try self.lexer.peek()) {
            if (next_token.kind == .RightParenthesis) {
                const right_parenthesis = try self.lexer.next();

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
                _ = try self.lexer.next(); // consume comma
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
            if ((try self.lexer.peek()).kind == .RightBracket) {
                break;
            }
            const element = try self.parseExpression(.{ .current_binding_power = 0 });
            elements.append(self.allocator, element) catch unreachable;

            const post_element_token = try self.lexer.peek();
            if (post_element_token.kind == .Comma) {
                _ = try self.lexer.next();
                if ((try self.lexer.peek()).kind == .RightBracket) {
                    break;
                }
                continue;
            }
            if (post_element_token.kind == .RightBracket) {
                break;
            }
            try self.diagnostic_store.emitErrorFromToken(post_element_token, "expected ',' or ']' after array element");
            return error.DiagnosticsEmitted;
        }

        const right_bracket_token = try self.lexer.next();
        if (right_bracket_token.kind != .RightBracket) {
            try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after array literal");
            return error.DiagnosticsEmitted;
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
        const left_bracket_token = try self.lexer.next();
        if (left_bracket_token.kind != .LeftBracket) {
            unreachable;
        }

        const index = self.allocator.create(ast.Node) catch unreachable;
        index.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const right_bracket_token = try self.lexer.next();
        if (right_bracket_token.kind != .RightBracket) {
            try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after index expression");
            return error.DiagnosticsEmitted;
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
        const dot_token = try self.lexer.next();
        if (dot_token.kind != .Dot) {
            unreachable;
        }

        const member_name_token = try self.lexer.next();
        if (member_name_token.kind != .Identifier) {
            try self.diagnostic_store.emitErrorFromToken(member_name_token, "expected member name after '.'");
            return error.DiagnosticsEmitted;
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
