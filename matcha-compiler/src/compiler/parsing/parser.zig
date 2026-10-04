const std = @import("std");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const ast = @import("ast");
const type_expressions = @import("type_expressions");

const TypeExpressionParser = @import("type_expression_parser.zig").TypeExpressionParser;
const PatternParser = @import("pattern_parser.zig").PatternParser;

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
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    next_node_id: ast.NodeId = 0,

    const ParseState = struct {
        current_binding_power: f64 = 0.0,
        allow_structure_literal: bool = true,
    };

    const OperatorInfo = struct {
        left_binding_power: f64,
        right_binding_power: f64,
    };

    pub fn init(lexer: lexing.Lexer, arena: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) Parser {
        return .{
            .lexer = lexer,
            .arena = arena,
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
            if (token.kind == .end_of_file) {
                break;
            }

            const statement = try self.parseStatement();
            try statements.append(self.arena, statement);
        }

        return ast.Program{
            .statements = try statements.toOwnedSlice(self.arena),
        };
    }

    fn parseStatement(self: *Parser) CompileError!ast.Node {
        if (self.startsItemDefinition()) {
            return try self.parseItemDefinition();
        }

        const token = try self.lexer.peek();
        return switch (token.kind) {
            .val, .@"var" => try self.parseBindingDeclaration(),
            .@"return" => try self.parseReturnStatement(),
            .@"if" => try self.parseIfStatement(),
            .loop => try self.parseLoopStatement(),
            .leave => try self.parseLeaveStatement(),
            .@"continue" => try self.parseContinueStatement(),
            .@"while" => try self.parseWhileStatement(),
            .@"for" => try self.parseForStatement(),
            .left_brace => try self.parseBlockStatement(),
            .identifier => if (self.startsAssignmentStatement())
                try self.parseAssignmentStatement(.{ .require_semicolon = true })
            else
                try self.parseExpressionStatement(),
            else => try self.parseExpressionStatement(),
        };
    }

    fn wrapExpressionStatement(self: *Parser, expression: ast.Node) !ast.Node {
        const expression_node = try self.arena.create(ast.Node);
        expression_node.* = expression;
        return self.createNode(.{
            .expression_statement = .{
                .expression = expression_node,
            },
        });
    }

    fn parseIfStatement(self: *Parser) CompileError!ast.Node {
        const if_token = try self.lexer.next();
        const if_form = try self.parseIfForm(if_token);
        return switch (if_form) {
            .statement => |if_statement| if_statement,
            .expression => |if_expression| {
                const semicolon = try self.lexer.next();
                if (semicolon.kind != .semicolon) {
                    try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after if expression");
                    return error.DiagnosticsEmitted;
                }
                return self.wrapExpressionStatement(if_expression);
            },
        };
    }

    fn parseLeaveStatement(self: *Parser) CompileError!ast.Node {
        const leave_token = try self.lexer.next();
        const semicolon = try self.lexer.next();
        if (semicolon.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after leave");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .leave_statement = .{
                .leave_token = leave_token,
            },
        });
    }

    fn parseContinueStatement(self: *Parser) CompileError!ast.Node {
        const continue_token = try self.lexer.next();
        const semicolon = try self.lexer.next();
        if (semicolon.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon, "expected ';' after continue");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .continue_statement = .{
                .continue_token = continue_token,
            },
        });
    }

    fn parseBlockStatement(self: *Parser) CompileError!ast.Node {
        const left_brace = try self.lexer.next();
        return self.parseBlock(left_brace);
    }

    fn startsStatementOnlyConstruct(token: lexing.Token) bool {
        return switch (token.kind) {
            .val,
            .@"var",
            .loop,
            .leave,
            .@"continue",
            .@"while",
            .@"for",
            .@"return",
            => true,
            else => false,
        };
    }

    fn isIdentifierNamed(token: lexing.Token, expected_name: []const u8) bool {
        return switch (token.kind) {
            .identifier => |name| std.mem.eql(u8, name, expected_name),
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
            .offset_in_source = token.offset_in_source,
            .length_in_source = token.length_in_source,
            .kind = .item,
        };
    }

    fn startsItemDefinition(self: *@This()) bool {
        var lookahead = self.lexer;
        const item_token = lookahead.next() catch return false;
        if (!isIdentifierNamed(item_token, "item")) {
            return false;
        }

        if ((lookahead.peek() catch return false).kind != .identifier) {
            return false;
        }
        _ = lookahead.next() catch return false;

        return switch ((lookahead.peek() catch return false).kind) {
            .left_parenthesis, .assign => true,
            else => false,
        };
    }

    fn parseBindingDeclaration(self: *Parser) CompileError!ast.Node {
        const val_or_var_token = try self.lexer.next(); // consume token

        const identifier_token = try self.lexer.next();
        if (identifier_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier_token, "expected identifier after 'val' or 'var'");
            return error.DiagnosticsEmitted;
        }

        const colon_or_equal_token = try self.lexer.next();
        const type_annotation: ?*type_expressions.TypeExpression = switch (colon_or_equal_token.kind) {
            .colon => block: {
                const parsed_type_annotation = try self.parseTypeAnnotation();

                const equal_token = try self.lexer.next();
                if (equal_token.kind != .assign) {
                    try self.diagnostic_store.emitErrorFromToken(equal_token, "expected '=' after type annotation in declaration");
                    return error.DiagnosticsEmitted;
                }

                break :block parsed_type_annotation;
            },
            .assign => null,
            else => {
                try self.diagnostic_store.emitErrorFromToken(colon_or_equal_token, "expected ':' or '=' after declaration name");
                return error.DiagnosticsEmitted;
            },
        };

        const value = try self.arena.create(ast.Node);
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after declaration");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .binding_declaration = .{
                .val_token = val_or_var_token,
                .name = identifier_token,
                .type_annotation = type_annotation,
                .value = value,
                .binding_mutability = switch (val_or_var_token.kind) {
                    .val => ast.BindingMutability.immutable,
                    .@"var" => ast.BindingMutability.mutable,
                    else => unreachable,
                },
            },
        });
    }

    fn parseItemDefinition(self: *@This()) CompileError!ast.Node {
        const item_token = contextualItemToken(try self.lexer.next()) orelse unreachable;

        const identifier_token = try self.lexer.next();
        if (identifier_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier_token, "expected identifier after 'item'");
            return error.DiagnosticsEmitted;
        }

        const post_identifier_token = try self.lexer.peek();
        if (post_identifier_token.kind == .left_parenthesis) {
            return try self.parseFunctionDefinition(item_token, identifier_token);
        }
        if (post_identifier_token.kind != .assign) {
            try self.diagnostic_store.emitErrorFromToken(post_identifier_token, "expected '(' or '=' after item name");
            return error.DiagnosticsEmitted;
        }
        _ = try self.lexer.next(); // consume equal sign

        const post_assign_token = try self.lexer.peek();
        if (post_assign_token.kind == .structure) {
            return self.parseStructureDefinition(item_token, identifier_token);
        }
        if (post_assign_token.kind == .@"union") {
            return self.parseUnionDefinition(item_token, identifier_token);
        }

        try self.diagnostic_store.emitErrorFromToken(post_assign_token, "expected 'structure' or 'union' after '=' in item definition");
        return error.DiagnosticsEmitted;
    }

    fn parseUnionDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) CompileError!ast.Node {
        const union_definition = try self.parseUnionDefinitionBody();
        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after union definition");
            return error.DiagnosticsEmitted;
        }
        return self.createNode(.{
            .item_definition = .{
                .item_token = item_token,
                .identifier_token = identifier_token,
                .definition = .{ .@"union" = union_definition },
            },
        });
    }

    fn parseUnionDefinitionBody(
        self: *@This(),
    ) CompileError!ast.UnionDefinition {
        const union_token = try self.lexer.next();
        if (union_token.kind != .@"union") {
            unreachable;
        }

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' after 'union'");
            return error.DiagnosticsEmitted;
        }

        var function_definitions = std.ArrayList(ast.Node){};
        var union_cases = std.ArrayList(ast.UnionCaseDeclaration){};
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .right_brace) {
                _ = try self.lexer.next();
                break;
            }

            if (self.startsItemDefinition()) {
                const item = try self.parseItemDefinition();
                switch (item.kind) {
                    .item_definition => |item_definition| {
                        switch (item_definition.definition) {
                            .function => try function_definitions.append(self.arena, item),
                            else => {
                                try self.diagnostic_store.emitErrorFromToken(item_definition.identifier_token, "expected function definition inside union body");
                                return error.DiagnosticsEmitted;
                            },
                        }
                    },
                    else => unreachable,
                }
                continue;
            }

            const case_name_token = try self.lexer.next();
            if (case_name_token.kind != .identifier) {
                try self.diagnostic_store.emitErrorFromToken(case_name_token, "expected case name or item definition in union body");
                return error.DiagnosticsEmitted;
            }

            var type_annotation: ?*type_expressions.TypeExpression = null;
            const post_case_name_token = try self.lexer.peek();
            if (post_case_name_token.kind == .colon) {
                _ = try self.lexer.next();
                type_annotation = try self.parseTypeAnnotation();
            }

            try union_cases.append(self.arena, .{
                .name = case_name_token,
                .type_annotation = type_annotation,
            });

            const post_case_token = try self.lexer.peek();
            if (post_case_token.kind == .comma) {
                _ = try self.lexer.next(); // consume comma and continue to next field
            } else if (post_case_token.kind != .right_brace) {
                try self.diagnostic_store.emitErrorFromToken(post_case_token, "expected ',' or '}' after union case");
                return error.DiagnosticsEmitted;
            }
        }

        if (union_cases.items.len <= 0) {
            try self.diagnostic_store.emitErrorFromToken(union_token, "union definitions must have at least one case");
            return error.DiagnosticsEmitted;
        }

        return .{
            .union_token = union_token,
            .cases = try union_cases.toOwnedSlice(self.arena),
            .function_definitions = try function_definitions.toOwnedSlice(self.arena),
        };
    }

    fn parseStructureDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) CompileError!ast.Node {
        const structure = try self.parseStructureDefinitionBody();
        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after structure definition");
            return error.DiagnosticsEmitted;
        }
        return self.createNode(.{
            .item_definition = .{
                .item_token = item_token,
                .identifier_token = identifier_token,
                .definition = .{ .structure = structure },
            },
        });
    }

    fn parseStructureDefinitionBody(
        self: *@This(),
    ) CompileError!ast.StructureDefinition {
        const structure_token = try self.lexer.next();
        if (structure_token.kind != .structure) {
            unreachable;
        }

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' after 'structure'");
            return error.DiagnosticsEmitted;
        }

        var function_definitions = std.ArrayList(ast.Node){};
        var fields = std.ArrayList(ast.StructureFieldDeclaration){};
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .right_brace) {
                _ = try self.lexer.next();
                break;
            }

            if (self.startsItemDefinition()) {
                const item = try self.parseItemDefinition();
                switch (item.kind) {
                    .item_definition => |item_definition| {
                        switch (item_definition.definition) {
                            .function => try function_definitions.append(self.arena, item),
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
            if (field_name_token.kind != .identifier) {
                try self.diagnostic_store.emitErrorFromToken(field_name_token, "expected field name or item definition in structure body");
                return error.DiagnosticsEmitted;
            }

            const colon_token = try self.lexer.next();
            if (colon_token.kind != .colon) {
                try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' after structure field name");
                return error.DiagnosticsEmitted;
            }

            const type_annotation = try self.parseTypeAnnotation();

            try fields.append(self.arena, .{
                .name = field_name_token,
                .type_annotation = type_annotation,
            });

            const post_field_token = try self.lexer.peek();
            if (post_field_token.kind == .semicolon) {
                _ = try self.lexer.next(); // consume semicolon and continue to next field
            } else if (post_field_token.kind != .right_brace) {
                try self.diagnostic_store.emitErrorFromToken(post_field_token, "expected ';' or '}' after structure field");
                return error.DiagnosticsEmitted;
            }
        }

        return .{
            .structure_token = structure_token,
            .fields = try fields.toOwnedSlice(self.arena),
            .function_definitions = try function_definitions.toOwnedSlice(self.arena),
        };
    }

    fn parseFunctionDefinition(
        self: *@This(),
        item_token: lexing.Token,
        identifier_token: lexing.Token,
    ) CompileError!ast.Node {
        const left_parenthesis_token = try self.lexer.next();
        if (left_parenthesis_token.kind != .left_parenthesis) {
            try self.diagnostic_store.emitErrorFromToken(left_parenthesis_token, "expected '(' after function name");
            return error.DiagnosticsEmitted;
        }

        var parameters = std.ArrayList(ast.ParameterDeclaration){};
        var next_token = try self.lexer.next();
        while (next_token.kind != .right_parenthesis) : (next_token = try self.lexer.next()) {
            if (next_token.kind != .identifier) {
                try self.diagnostic_store.emitErrorFromToken(next_token, "expected parameter name");
                return error.DiagnosticsEmitted;
            }
            const parameter_name_token = next_token;

            const colon_token = try self.lexer.next();
            if (colon_token.kind != .colon) {
                try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' after parameter name");
                return error.DiagnosticsEmitted;
            }

            const type_annotation = try self.parseTypeAnnotation();

            try parameters.append(self.arena, .{
                .name = parameter_name_token,
                .type_annotation = type_annotation,
            });

            const post_parameter_token = try self.lexer.peek();
            if (post_parameter_token.kind == .comma) {
                _ = try self.lexer.next(); // consume comma and continue to next parameter
            } else if (post_parameter_token.kind != .right_parenthesis) {
                try self.diagnostic_store.emitErrorFromToken(post_parameter_token, "expected ',' or ')' after parameter");
                return error.DiagnosticsEmitted;
            }
        }

        if (next_token.kind != .right_parenthesis) {
            try self.diagnostic_store.emitErrorFromToken(next_token, "expected ')' after parameter list");
            return error.DiagnosticsEmitted;
        }

        const colon_token = try self.lexer.next();
        if (colon_token.kind != .colon) {
            try self.diagnostic_store.emitErrorFromToken(colon_token, "expected ':' before function return type");
            return error.DiagnosticsEmitted;
        }

        const return_type_annotation = try self.parseTypeAnnotation();

        const assign_token = try self.lexer.next();
        if (assign_token.kind != .assign) {
            try self.diagnostic_store.emitErrorFromToken(assign_token, "expected '=' before function body");
            return error.DiagnosticsEmitted;
        }

        const body_expression = try self.arena.create(ast.Node);
        body_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after function definition");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .item_definition = .{
                .item_token = item_token,
                .identifier_token = identifier_token,
                .definition = .{
                    .function = .{
                        .parameters = try parameters.toOwnedSlice(self.arena),
                        .return_type_annotation = return_type_annotation,
                        .body_expression = body_expression,
                    },
                },
            },
        });
    }

    fn parseTypeAnnotation(self: *@This()) CompileError!*type_expressions.TypeExpression {
        var type_expression_parser = TypeExpressionParser.init(&self.lexer, self.arena, self.diagnostic_store);
        return type_expression_parser.parse();
    }

    fn parseReturnStatement(self: *@This()) CompileError!ast.Node {
        const return_token = try self.lexer.next();
        if (return_token.kind != .@"return") {
            unreachable;
        }

        const post_return_token = try self.lexer.peek();
        if (post_return_token.kind == .semicolon) {
            _ = try self.lexer.next(); // consume semicolon
            return self.createNode(.{
                .return_statement = .{
                    .return_token = return_token,
                    .value = null,
                },
            });
        }

        const expression = try self.arena.create(ast.Node);
        expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after return value");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .return_statement = .{
                .return_token = return_token,
                .value = expression,
            },
        });
    }

    fn parseLoopStatement(self: *@This()) CompileError!ast.Node {
        const loop_token = try self.lexer.next();
        if (loop_token.kind != .loop) {
            unreachable;
        }

        const left_brace = try self.lexer.next();
        if (left_brace.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace, "expected '{' after 'loop'");
            return error.DiagnosticsEmitted;
        }

        const body_block = try self.arena.create(ast.Node);
        body_block.* = try self.parseBlock(left_brace);

        return self.createNode(.{
            .loop = .{
                .loop_token = loop_token,
                .body_block = body_block,
            },
        });
    }

    fn parseWhileStatement(self: *@This()) CompileError!ast.Node {
        const while_token = try self.lexer.next();
        if (while_token.kind != .@"while") {
            unreachable;
        }

        const condition = try self.arena.create(ast.Node);
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_literal = false,
        });

        var update: ?*ast.Node = null;
        var post_condition_token = try self.lexer.peek();
        if (post_condition_token.kind == .colon) {
            _ = try self.lexer.next();
            const assignment_statement = try self.arena.create(ast.Node);
            assignment_statement.* = try self.parseAssignmentStatement(.{ .require_semicolon = false });
            update = assignment_statement;
            post_condition_token = try self.lexer.peek();
        }

        if (post_condition_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(post_condition_token, "expected '{' after while condition");
            return error.DiagnosticsEmitted;
        }
        const left_brace_token = try self.lexer.next();

        const body = try self.arena.create(ast.Node);
        body.* = try self.parseBlock(left_brace_token);

        return self.createNode(.{
            .@"while" = .{
                .while_token = while_token,
                .condition = condition,
                .update = update,
                .body_block = body,
            },
        });
    }

    fn parseForStatement(self: *@This()) CompileError!ast.Node {
        const for_token = try self.lexer.next();
        if (for_token.kind != .@"for") {
            unreachable;
        }

        const item_name = try self.lexer.next();
        if (item_name.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(item_name, "expected loop variable name after 'for'");
            return error.DiagnosticsEmitted;
        }

        const in_token = try self.lexer.next();
        if (in_token.kind != .in) {
            try self.diagnostic_store.emitErrorFromToken(in_token, "expected 'in' after loop variable");
            return error.DiagnosticsEmitted;
        }

        const iterable = try self.arena.create(ast.Node);
        iterable.* = try self.parseExpression(.{
            .current_binding_power = 0.0,
            .allow_structure_literal = false,
        });

        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' after for iterable");
            return error.DiagnosticsEmitted;
        }

        const body = try self.arena.create(ast.Node);
        body.* = try self.parseBlock(left_brace_token);

        return self.createNode(.{
            .for_in = .{
                .for_token = for_token,
                .item_name = item_name,
                .in_token = in_token,
                .iterable = iterable,
                .body_block = body,
            },
        });
    }

    fn parseAssignmentStatement(self: *@This(), options: struct { require_semicolon: bool }) CompileError!ast.Node {
        const target = try self.arena.create(ast.Node);
        target.* = try self.parsePlaceExpression();

        const assignment_token = try self.lexer.next();
        const assignment_operator = switch (assignment_token.kind) {
            .assign => ast.AssignmentOperator.assign,
            .plus_assign => ast.AssignmentOperator{ .compound = .add },
            .minus_assign => ast.AssignmentOperator{ .compound = .subtract },
            .asterisk_assign => ast.AssignmentOperator{ .compound = .multiply },
            else => null,
        };
        if (assignment_operator == null) {
            try self.diagnostic_store.emitErrorFromToken(assignment_token, "expected assignment operator");
            return error.DiagnosticsEmitted;
        }

        const value = try self.arena.create(ast.Node);
        value.* = try self.parseExpression(.{ .current_binding_power = 0 });

        if (options.require_semicolon) {
            const semicolon_token = try self.lexer.next();
            if (semicolon_token.kind != .semicolon) {
                try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after assignment");
                return error.DiagnosticsEmitted;
            }
        }

        return self.createNode(.{
            .assignment_statement = .{
                .target = target,
                .operator = assignment_operator.?,
                .assignment_token = assignment_token,
                .value = value,
            },
        });
    }

    fn startsAssignmentStatement(self: *@This()) bool {
        var lookahead = self.lexer;
        if ((lookahead.peek() catch return false).kind != .identifier) return false;

        _ = lookahead.next() catch return false;
        while (true) {
            switch ((lookahead.peek() catch return false).kind) {
                .dot => {
                    _ = lookahead.next() catch return false;
                    if ((lookahead.peek() catch return false).kind != .identifier) {
                        return false;
                    }
                    _ = lookahead.next() catch return false;
                },
                .left_bracket => {
                    _ = lookahead.next() catch return false;
                    var bracket_depth: usize = 1;
                    while (bracket_depth > 0) {
                        const next_token = lookahead.next() catch return false;
                        switch (next_token.kind) {
                            .left_bracket => bracket_depth += 1,
                            .right_bracket => bracket_depth -= 1,
                            .end_of_file, .semicolon => return false,
                            else => {},
                        }
                    }
                },
                else => break,
            }
        }

        return switch ((lookahead.peek() catch return false).kind) {
            .assign, .plus_assign, .minus_assign, .asterisk_assign => true,
            else => false,
        };
    }

    fn parsePlaceExpression(self: *@This()) CompileError!ast.Node {
        const identifier_token = try self.lexer.next();
        if (identifier_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier_token, "expected identifier");
            return error.DiagnosticsEmitted;
        }

        var target = self.createNode(.{ .identifier = identifier_token });
        while (true) {
            switch ((try self.lexer.peek()).kind) {
                .dot => target = try self.parseMemberExpression(target),
                .left_bracket => target = try self.parseIndexExpression(target),
                else => break,
            }
        }

        return target;
    }

    fn parseIfForm(self: *Parser, if_token: lexing.Token) CompileError!ParsedIf {
        if (if_token.kind != .@"if") {
            try self.diagnostic_store.emitErrorFromToken(if_token, "expected 'if'");
            return error.DiagnosticsEmitted;
        }

        const condition = try self.arena.create(ast.Node);
        condition.* = try self.parseExpression(.{
            .current_binding_power = 0,
            .allow_structure_literal = false,
        });

        const then_branch_left_brace_token = try self.lexer.next();
        if (then_branch_left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(then_branch_left_brace_token, "expected '{' after if condition");
            return error.DiagnosticsEmitted;
        }

        const then_branch = try self.arena.create(ast.Node);

        then_branch.* = try self.parseBlock(then_branch_left_brace_token);

        const post_then_branch_token = try self.lexer.peek();
        if (post_then_branch_token.kind == .@"else") {
            const else_token = try self.lexer.next();

            const else_branch_left_brace_token = try self.lexer.next();
            if (else_branch_left_brace_token.kind != .left_brace) {
                try self.diagnostic_store.emitErrorFromToken(else_branch_left_brace_token, "expected '{' after 'else'");
                return error.DiagnosticsEmitted;
            }
            const else_block = try self.arena.create(ast.Node);
            else_block.* = try self.parseBlock(else_branch_left_brace_token);

            return .{
                .expression = self.createNode(.{
                    .if_expression = .{
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
                    .if_statement = .{
                        .if_token = if_token,
                        .condition = condition,
                        .then_branch = then_branch,
                    },
                }),
            };
        }
    }

    fn parseMatchExpression(self: *Parser, match_token: lexing.Token) CompileError!ast.Node {
        if (match_token.kind != .match) {
            try self.diagnostic_store.emitErrorFromToken(match_token, "expected 'match'");
            return error.DiagnosticsEmitted;
        }

        if ((try self.lexer.peek()).kind == .left_brace) {
            return self.parseSubjectlessMatchExpression(match_token);
        }

        const subject = try self.arena.create(ast.Node);
        subject.* = try self.parseExpression(.{
            .current_binding_power = 0,
            .allow_structure_literal = false,
        });
        try self.expectMatchBodyStart();

        var arms = std.ArrayList(ast.MatchArm){};
        var else_token: ?lexing.Token = null;
        var else_arm_expression: ?*ast.Node = null;
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .right_brace) {
                _ = try self.lexer.next();
                break;
            }
            try self.rejectArmAfterElseArm(next_token, else_token);

            if (next_token.kind == .@"else") {
                else_token = try self.lexer.next();
                _ = try self.expectFatArrow("expected '=>' after 'else' in match expression");
                else_arm_expression = try self.arena.create(ast.Node);
                else_arm_expression.?.* = try self.parseExpression(.{ .current_binding_power = 0 });
            } else {
                const pattern = try self.parsePattern();
                const fat_arrow_token = try self.expectFatArrow("expected '=>' in match arm");
                const body_expression = try self.arena.create(ast.Node);
                body_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });
                try arms.append(self.arena, .{
                    .pattern = pattern,
                    .fat_arrow_token = fat_arrow_token,
                    .body_expression = body_expression,
                });
            }
            try self.expectMatchArmSeparator();
        }

        return self.createNode(.{
            .match_expression = .{
                .match_token = match_token,
                .subject = subject,
                .arms = try arms.toOwnedSlice(self.arena),
                .else_token = else_token,
                .else_arm_expression = else_arm_expression,
            },
        });
    }

    fn parseSubjectlessMatchExpression(self: *Parser, match_token: lexing.Token) CompileError!ast.Node {
        try self.expectMatchBodyStart();

        var arms = std.ArrayList(ast.SubjectlessMatchArm){};
        var else_token: ?lexing.Token = null;
        var else_arm_expression: ?*ast.Node = null;
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .right_brace) {
                _ = try self.lexer.next();
                break;
            }
            try self.rejectArmAfterElseArm(next_token, else_token);

            if (next_token.kind == .@"else") {
                else_token = try self.lexer.next();
                _ = try self.expectFatArrow("expected '=>' after 'else' in match expression");
                else_arm_expression = try self.arena.create(ast.Node);
                else_arm_expression.?.* = try self.parseExpression(.{ .current_binding_power = 0 });
            } else {
                const condition = try self.arena.create(ast.Node);
                condition.* = try self.parseExpression(.{ .current_binding_power = 0 });
                const fat_arrow_token = try self.expectFatArrow("expected '=>' in match arm");
                const body_expression = try self.arena.create(ast.Node);
                body_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });
                try arms.append(self.arena, .{
                    .condition = condition,
                    .body_expression = body_expression,
                    .fat_arrow_token = fat_arrow_token,
                });
            }
            try self.expectMatchArmSeparator();
        }

        return self.createNode(.{
            .subjectless_match_expression = .{
                .match_token = match_token,
                .arms = try arms.toOwnedSlice(self.arena),
                .else_token = else_token,
                .else_arm_expression = else_arm_expression,
            },
        });
    }

    fn expectMatchBodyStart(self: *Parser) CompileError!void {
        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' to start match body");
            return error.DiagnosticsEmitted;
        }
    }

    fn rejectArmAfterElseArm(self: *Parser, next_token: lexing.Token, else_token: ?lexing.Token) CompileError!void {
        if (else_token != null) {
            try self.diagnostic_store.emitErrorFromToken(next_token, "'else' must be the last match arm");
            return error.DiagnosticsEmitted;
        }
    }

    fn expectFatArrow(self: *Parser, missing_fat_arrow_message: []const u8) CompileError!lexing.Token {
        const fat_arrow_token = try self.lexer.next();
        if (fat_arrow_token.kind != .fat_arrow) {
            try self.diagnostic_store.emitErrorFromToken(fat_arrow_token, missing_fat_arrow_message);
            return error.DiagnosticsEmitted;
        }

        return fat_arrow_token;
    }

    fn expectMatchArmSeparator(self: *Parser) CompileError!void {
        const separator_or_end = try self.lexer.peek();
        switch (separator_or_end.kind) {
            .comma => {
                _ = try self.lexer.next();
            },
            .right_brace => {},
            else => {
                try self.diagnostic_store.emitErrorFromToken(separator_or_end, "expected ',' or '}' after match arm");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parsePattern(self: *Parser) CompileError!ast.Pattern {
        var pattern_parser = PatternParser.init(&self.lexer, self.arena, self.diagnostic_store, &self.next_node_id);
        return pattern_parser.parse();
    }

    fn parseBlock(self: *Parser, left_brace_token: lexing.Token) CompileError!ast.Node {
        var statements = std.ArrayList(ast.Node){};
        var result: ?*ast.Node = null;

        while (true) {
            const block_item = try self.parseBlockItem();
            switch (block_item) {
                .statement => |statement| {
                    try statements.append(self.arena, statement);
                    const post_statement_token = try self.lexer.peek();
                    if (post_statement_token.kind == .right_brace) {
                        // Done parsing the block. It finished with a statement, so there is no result expression.
                        break;
                    }
                },
                .expression => |expression| {
                    const expression_node = try self.arena.create(ast.Node);
                    expression_node.* = expression;
                    result = expression_node;
                    // Done parsing the block. It finished with an expression, so we set the result and break out of the loop.
                    break;
                },
            }
        }

        const right_brace_token = try self.lexer.next();

        return self.createNode(.{
            .block = .{
                .left_brace = left_brace_token,
                .statements = try statements.toOwnedSlice(self.arena),
                .result = result,
                .right_brace = right_brace_token,
            },
        });
    }

    fn parseBlockItem(self: *Parser) CompileError!BlockItem {
        const token = try self.lexer.peek();
        if (Parser.startsStatementOnlyConstruct(token)) {
            const statement = try self.parseStatement();
            return .{ .statement = statement };
        }

        switch (token.kind) {
            .@"if" => {
                return try self.parseIfBlockItem();
            },
            .identifier => if (self.startsAssignmentStatement()) {
                const assignment_statement = try self.parseAssignmentStatement(.{ .require_semicolon = true });
                return .{ .statement = assignment_statement };
            },
            else => {},
        }

        const expression = try self.parseExpression(.{ .current_binding_power = 0 });
        const post_expression_token = try self.lexer.peek();
        switch (post_expression_token.kind) {
            .semicolon => {
                _ = try self.lexer.next(); // consume semicolon
                return .{ .statement = try self.wrapExpressionStatement(expression) };
            },
            .right_brace => return .{
                .expression = expression,
            },
            else => {
                try self.diagnostic_store.emitErrorFromToken(post_expression_token, "expected ';' after expression");
                return error.DiagnosticsEmitted;
            },
        }
    }

    fn parseIfBlockItem(self: *Parser) CompileError!BlockItem {
        const if_token = try self.lexer.next();
        const if_form = try self.parseIfForm(if_token);
        return switch (if_form) {
            .statement => |if_statement| .{ .statement = if_statement },
            .expression => |if_expression| {
                const post_if_expression_token = try self.lexer.peek();
                switch (post_if_expression_token.kind) {
                    .semicolon => {
                        _ = try self.lexer.next();
                        return .{ .statement = try self.wrapExpressionStatement(if_expression) };
                    },
                    .right_brace => return .{ .expression = if_expression },
                    else => {
                        try self.diagnostic_store.emitErrorFromToken(post_if_expression_token, "expected ';' after if expression");
                        return error.DiagnosticsEmitted;
                    },
                }
            },
        };
    }

    fn parseExpressionStatement(self: *Parser) CompileError!ast.Node {
        const expression = try self.parseExpression(.{ .current_binding_power = 0 });

        const semicolon_token = try self.lexer.next();
        if (semicolon_token.kind != .semicolon) {
            try self.diagnostic_store.emitErrorFromToken(semicolon_token, "expected ';' after expression");
            return error.DiagnosticsEmitted;
        }

        return self.wrapExpressionStatement(expression);
    }

    pub fn parseExpression(self: *Parser, state: ParseState) CompileError!ast.Node {
        const token = try self.lexer.next();
        var left_hand_side = try self.parsePrefixExpression(token, state);

        if (token.kind == .left_parenthesis) {
            const next_token = try self.lexer.peek();
            if (next_token.kind != .right_parenthesis) {
                try self.diagnostic_store.emitErrorFromToken(next_token, "expected ')' to close grouped expression");
                return error.DiagnosticsEmitted;
            }
            _ = try self.lexer.next();
        }

        while (true) {
            // Find the next operator without consuming it
            const next_token = try self.lexer.peek();

            if (next_token.kind == .left_parenthesis) {
                left_hand_side = try self.parseCalleeExpression(left_hand_side);
                continue;
            }

            if (next_token.kind == .dot) {
                left_hand_side = try self.parseMemberExpression(left_hand_side);
                continue;
            }

            if (next_token.kind == .left_bracket) {
                left_hand_side = try self.parseIndexExpression(left_hand_side);
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
                const right_hand_side = try self.arena.create(ast.Node);
                right_hand_side.* = try self.parseExpression(.{
                    .current_binding_power = operator.right_binding_power,
                    .allow_structure_literal = state.allow_structure_literal,
                });

                const left_hand_side_pointer = try self.arena.create(ast.Node);
                left_hand_side_pointer.* = left_hand_side;

                left_hand_side = self.createNode(.{
                    .binary_expression = .{
                        .operator = switch (next_token.kind) {
                            .plus => ast.BinaryOperator.add,
                            .minus => ast.BinaryOperator.subtract,
                            .asterisk => ast.BinaryOperator.multiply,
                            .slash => ast.BinaryOperator.divide,
                            .equal_equal => ast.BinaryOperator.equal,
                            .not_equal => ast.BinaryOperator.not_equal,
                            .less_than => ast.BinaryOperator.less_than,
                            .less_than_or_equal => ast.BinaryOperator.less_than_or_equal,
                            .greater_than => ast.BinaryOperator.greater_than,
                            .greater_than_or_equal => ast.BinaryOperator.greater_than_or_equal,
                            .@"and" => ast.BinaryOperator.@"and",
                            .@"or" => ast.BinaryOperator.@"or",
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
            .@"or" => .{
                .left_binding_power = 1.0,
                .right_binding_power = 1.1,
            },
            .@"and" => .{
                .left_binding_power = 2.0,
                .right_binding_power = 2.1,
            },
            .equal_equal, .not_equal => .{
                .left_binding_power = 3.0,
                .right_binding_power = 3.1,
            },
            .less_than, .less_than_or_equal, .greater_than, .greater_than_or_equal => .{
                .left_binding_power = 4.0,
                .right_binding_power = 4.1,
            },
            .plus, .minus => .{
                .left_binding_power = 5.0,
                .right_binding_power = 5.1,
            },
            .asterisk, .slash => .{
                .left_binding_power = 6.0,
                .right_binding_power = 6.1,
            },
            else => null,
        };
    }

    fn getPrefixOperatorBindingPower(kind: lexing.TokenKind) ?f64 {
        return switch (kind) {
            .minus, .not => 7.0,
            else => null,
        };
    }

    fn parsePrefixExpression(self: *Parser, token: lexing.Token, state: ParseState) CompileError!ast.Node {
        return switch (token.kind) {
            .int_literal => self.createNode(.{ .integer_literal = token }),
            .boolean_literal => self.createNode(.{ .boolean_literal = token }),
            .string_literal => self.createNode(.{ .string_literal = token }),
            .identifier => try self.parseIdentifierExpression(token, state),
            .dot => try self.parseDotExpression(token, state),
            .@"if" => try self.parseIfExpression(token),
            .match => try self.parseMatchExpression(token),
            .left_bracket => try self.parseArrayLiteral(token),
            .left_parenthesis => try self.parseExpression(.{ .current_binding_power = 0 }),
            .left_brace => try self.parseBlock(token),
            .@"else" => {
                try self.diagnostic_store.emitErrorFromToken(token, "unexpected 'else'");
                return error.DiagnosticsEmitted;
            },
            .minus => try self.parseUnaryExpression(token, .negate, state),
            .not => try self.parseUnaryExpression(token, .not, state),
            else => {
                try self.diagnostic_store.emitErrorFromToken(token, "expected expression");
                return error.DiagnosticsEmitted;
            },
        };
    }

    fn parseIdentifierExpression(self: *Parser, token: lexing.Token, state: ParseState) CompileError!ast.Node {
        if (isIdentifierNamed(token, "unit")) {
            return self.createNode(.{ .unit_literal = token });
        }

        const post_identifier_token = try self.lexer.peek();
        if (state.allow_structure_literal and post_identifier_token.kind == .left_brace) {
            return self.parseQualifiedStructureLiteral(token);
        }
        return self.createNode(.{ .identifier = token });
    }

    fn parseDotExpression(self: *Parser, token: lexing.Token, state: ParseState) CompileError!ast.Node {
        const post_dot_token = try self.lexer.peek();
        if (post_dot_token.kind == .identifier) {
            return self.parseImplicitMemberExpression(token);
        }
        if (state.allow_structure_literal and post_dot_token.kind == .left_brace) {
            return self.parseStructureLiteral(token);
        }

        try self.diagnostic_store.emitErrorFromToken(token, "expected '{' after '.' in anonymous structure literal");

        return error.DiagnosticsEmitted;
    }

    fn parseImplicitMemberExpression(self: *@This(), dot_token: lexing.Token) CompileError!ast.Node {
        const identifier = try self.lexer.next();
        if (identifier.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(identifier, "expected identifier to start implicit member expression");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .implicit_member_expression = .{
                .dot_token = dot_token,
                .member_name_token = identifier,
            },
        });
    }

    fn parseIfExpression(self: *Parser, token: lexing.Token) CompileError!ast.Node {
        const if_form = try self.parseIfForm(token);
        return switch (if_form) {
            .statement => {
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
    ) CompileError!ast.Node {
        const prefix_binding_power = getPrefixOperatorBindingPower(token.kind) orelse unreachable;

        const operand = try self.arena.create(ast.Node);
        operand.* = try self.parseExpression(.{
            .current_binding_power = prefix_binding_power,
            .allow_structure_literal = state.allow_structure_literal,
        });

        return self.createNode(.{
            .unary_expression = .{
                .operator = operator,
                .operator_token = token,
                .operand = operand,
            },
        });
    }

    fn parseQualifiedStructureLiteral(self: *@This(), structure_name: lexing.Token) CompileError!ast.Node {
        const parsed_fields = try self.parseStructureFieldInitializers();

        return self.createNode(.{
            .qualified_structure_literal = .{
                .structure_name = structure_name,
                .fields = parsed_fields.fields,
            },
        });
    }

    fn parseStructureLiteral(self: *@This(), dot_token: lexing.Token) CompileError!ast.Node {
        const parsed_fields = try self.parseStructureFieldInitializers();

        return self.createNode(.{
            .structure_literal = .{
                .dot_token = dot_token,
                .left_brace = parsed_fields.left_brace_token,
                .fields = parsed_fields.fields,
            },
        });
    }

    fn parseStructureFieldInitializers(self: *@This()) CompileError!struct {
        left_brace_token: lexing.Token,
        fields: []ast.StructureFieldInitializer,
    } {
        const left_brace_token = try self.lexer.next();
        if (left_brace_token.kind != .left_brace) {
            try self.diagnostic_store.emitErrorFromToken(left_brace_token, "expected '{' to start structure literal");
            return error.DiagnosticsEmitted;
        }

        var fields = std.ArrayList(ast.StructureFieldInitializer){};
        while (true) {
            const next_token = try self.lexer.peek();
            if (next_token.kind == .right_brace) {
                _ = try self.lexer.next();
                break;
            }

            const field_name_token = try self.lexer.next();
            if (field_name_token.kind != .identifier) {
                try self.diagnostic_store.emitErrorFromToken(field_name_token, "expected field name in structure construction");
                return error.DiagnosticsEmitted;
            }

            const assign_token = try self.lexer.next();
            if (assign_token.kind != .assign) {
                try self.diagnostic_store.emitErrorFromToken(assign_token, "expected '=' after field name in structure construction");
                return error.DiagnosticsEmitted;
            }

            const value_expression = try self.arena.create(ast.Node);
            value_expression.* = try self.parseExpression(.{ .current_binding_power = 0 });

            try fields.append(self.arena, .{
                .name = field_name_token,
                .assign_token = assign_token,
                .value = value_expression,
            });

            const post_field_token = try self.lexer.peek();
            if (post_field_token.kind == .comma) {
                _ = try self.lexer.next(); // consume comma and continue to next field
            } else if (post_field_token.kind != .right_brace) {
                try self.diagnostic_store.emitErrorFromToken(post_field_token, "expected ',' or '}' after structure field");
                return error.DiagnosticsEmitted;
            }
        }

        return .{
            .left_brace_token = left_brace_token,
            .fields = try fields.toOwnedSlice(self.arena),
        };
    }

    pub fn parseCalleeExpression(self: *@This(), left_hand_size: ast.Node) CompileError!ast.Node {
        const left_parenthesis = try self.lexer.next();
        if (left_parenthesis.kind != .left_parenthesis) {
            try self.diagnostic_store.emitErrorFromToken(left_parenthesis, "expected '(' to start argument list");
            return error.DiagnosticsEmitted;
        }

        var arguments = std.ArrayList(ast.Node){};
        while (true) {
            if ((try self.lexer.peek()).kind == .right_parenthesis) {
                break;
            }
            const argument = try self.parseExpression(.{ .current_binding_power = 0.0 });
            try arguments.append(self.arena, argument);

            const post_argument_token = try self.lexer.peek();
            if (post_argument_token.kind == .comma) {
                _ = try self.lexer.next();
                continue;
            }
            if (post_argument_token.kind == .right_parenthesis) {
                break;
            }
            try self.diagnostic_store.emitErrorFromToken(post_argument_token, "expected ',' or ')' after call argument");
            return error.DiagnosticsEmitted;
        }

        const right_parenthesis = try self.lexer.next();
        const callee = try self.arena.create(ast.Node);
        callee.* = left_hand_size;

        return self.createNode(.{
            .call_expression = .{
                .callee = callee,
                .left_parenthesis = left_parenthesis,
                .arguments = try arguments.toOwnedSlice(self.arena),
                .right_parenthesis = right_parenthesis,
            },
        });
    }

    fn parseArrayLiteral(self: *@This(), left_bracket_token: lexing.Token) CompileError!ast.Node {
        if (left_bracket_token.kind != .left_bracket) {
            unreachable;
        }

        var elements = std.ArrayList(ast.Node){};
        while (true) {
            if ((try self.lexer.peek()).kind == .right_bracket) {
                break;
            }
            const element = try self.parseExpression(.{ .current_binding_power = 0 });
            try elements.append(self.arena, element);

            const post_element_token = try self.lexer.peek();
            if (post_element_token.kind == .comma) {
                _ = try self.lexer.next();
                if ((try self.lexer.peek()).kind == .right_bracket) {
                    break;
                }
                continue;
            }
            if (post_element_token.kind == .right_bracket) {
                break;
            }
            try self.diagnostic_store.emitErrorFromToken(post_element_token, "expected ',' or ']' after array element");
            return error.DiagnosticsEmitted;
        }

        const right_bracket_token = try self.lexer.next();
        if (right_bracket_token.kind != .right_bracket) {
            try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after array literal");
            return error.DiagnosticsEmitted;
        }

        return self.createNode(.{
            .array_literal = .{
                .left_bracket = left_bracket_token,
                .elements = try elements.toOwnedSlice(self.arena),
                .right_bracket = right_bracket_token,
            },
        });
    }

    fn parseIndexExpression(self: *@This(), left_hand_side: ast.Node) CompileError!ast.Node {
        const left_bracket_token = try self.lexer.next();
        if (left_bracket_token.kind != .left_bracket) {
            unreachable;
        }

        const index = try self.arena.create(ast.Node);
        index.* = try self.parseExpression(.{ .current_binding_power = 0 });

        const right_bracket_token = try self.lexer.next();
        if (right_bracket_token.kind != .right_bracket) {
            try self.diagnostic_store.emitErrorFromToken(right_bracket_token, "expected ']' after index expression");
            return error.DiagnosticsEmitted;
        }

        const base = try self.arena.create(ast.Node);
        base.* = left_hand_side;

        return self.createNode(.{
            .index_expression = .{
                .base = base,
                .left_bracket = left_bracket_token,
                .index = index,
                .right_bracket = right_bracket_token,
            },
        });
    }

    fn parseMemberExpression(self: *@This(), left_hand_side: ast.Node) CompileError!ast.Node {
        const dot_token = try self.lexer.next();
        if (dot_token.kind != .dot) {
            unreachable;
        }

        const member_name_token = try self.lexer.next();
        if (member_name_token.kind != .identifier) {
            try self.diagnostic_store.emitErrorFromToken(member_name_token, "expected member name after '.'");
            return error.DiagnosticsEmitted;
        }

        const base = try self.arena.create(ast.Node);
        base.* = left_hand_side;

        return self.createNode(.{
            .member_expression = .{
                .base = base,
                .dot_token = dot_token,
                .member_name_token = member_name_token,
            },
        });
    }
};
