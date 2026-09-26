const std = @import("std");
const expect = @import("testing").expect;
const setupParserPipeline = @import("testing").setupParserPipeline;

test "Parser > parse: binds multiplication tighter than addition" {
    const source = "val result = 1 + 2 * 3;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .BinaryExpression = .{
                .operator = .Add,
                .left = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
                .right = .{ .kind = .{ .BinaryExpression = .{
                    .operator = .Multiply,
                    .left = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
                    .right = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 3 } } } },
                } } },
            } } },
        } } },
    } });
}

test "Parser > parse: orders arithmetic, comparison, and boolean operators by precedence" {
    const source = "val result = 1 + 2 >= 3 and false or true;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .BinaryExpression = .{
                .operator = .Or,
                .left = .{ .kind = .{ .BinaryExpression = .{
                    .operator = .And,
                    .left = .{ .kind = .{ .BinaryExpression = .{
                        .operator = .GreaterThanOrEqual,
                        .left = .{ .kind = .{ .BinaryExpression = .{
                            .operator = .Add,
                            .left = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
                            .right = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
                        } } },
                        .right = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 3 } } } },
                    } } },
                    .right = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = false } } } },
                } } },
                .right = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = true } } } },
            } } },
        } } },
    } });
}

test "Parser > parse: binds unary not tighter than and" {
    const source = "val result = not false and true;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .BinaryExpression = .{
                .operator = .And,
                .left = .{ .kind = .{ .UnaryExpression = .{
                    .operator = .Not,
                    .operand = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = false } } } },
                } } },
                .right = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = true } } } },
            } } },
        } } },
    } });
}

test "Parser > parse: allows an identifier-led block result after statements" {
    const source =
        \\val result = {
        \\    val left = 1;
        \\    left + right
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .Block = .{
                .statements = .{
                    .{ .kind = .{ .BindingDeclaration = .{} } },
                },
                .result = .{ .kind = .{ .BinaryExpression = .{
                    .operator = .Add,
                    .left = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "left" } } } },
                    .right = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "right" } } } },
                } } },
            } } },
        } } },
    } });
}

test "Parser > parse: keeps a block statement-only when it ends with an if statement" {
    const source =
        \\{
        \\    if true { val scoped = 1; }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .Block = .{
            .statements = .{
                .{ .kind = .{ .IfStatement = .{} } },
            },
            .result = null,
        } } },
    } });
}

test "Parser > parse: treats a bare identifier before a while body as the condition" {
    const source = "while is_ready { continue; }";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .While = .{
            .condition = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "is_ready" } } } },
        } } },
    } });
}

test "Parser > parse: treats unit as a literal when used as an expression" {
    const source = "val value = unit;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .UnitLiteral = .{} } },
        } } },
    } });
}

test "Parser > parse: allows item as a binding name" {
    const source = "val item = 1;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .name = .{ .kind = .{ .Identifier = "item" } },
        } } },
    } });
}

test "Parser > parse: allows item as a for-in binding name" {
    const source = "for item in items { continue; }";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ForIn = .{
            .item_name = .{ .kind = .{ .Identifier = "item" } },
        } } },
    } });
}

test "Parser > parse: allows item as an identifier expression" {
    const source = "val value = item;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "item" } } } },
        } } },
    } });
}

test "Parser > parse: allows item as a structure field name" {
    const source = "item Point = structure { item: int; };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .definition = .{ .Structure = .{
                .fields = .{
                    .{ .name = .{ .kind = .{ .Identifier = "item" } } },
                },
            } },
        } } },
    } });
}

test "Parser > parse: allows item as a member name" {
    const source = "val value = point.item;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .member_name_token = .{ .kind = .{ .Identifier = "item" } },
            } } },
        } } },
    } });
}

test "Parser > parse: recognizes item as a structure definition keyword" {
    const source = "item Point = structure { x: int; };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "Point" } },
            .definition = .{ .Structure = .{} },
        } } },
    } });
}

test "Parser > parse: recognizes item as a function definition keyword inside a structure" {
    const source =
        \\item Point = structure {
        \\    item get(self: Point): int = 1;
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .definition = .{ .Structure = .{
                .function_definitions = .{
                    .{ .kind = .{ .ItemDefinition = .{
                        .identifier_token = .{ .kind = .{ .Identifier = "get" } },
                        .definition = .{ .Function = .{} },
                    } } },
                },
            } },
        } } },
    } });
}

test "Parser > parse: parses member access on an identifier" {
    const source = "val value = point.x;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "point" } } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
        } } },
    } });
}

test "Parser > parse: parses nested member access" {
    const source = "val value = user.location.x;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "user" } } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "location" } },
                } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
        } } },
    } });
}

test "Parser > parse: parses member access on a parenthesized structure literal" {
    const source = "val value = (Point { x = 1 }).x;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .QualifiedStructureLiteral = .{
                    .structure_name = .{ .kind = .{ .Identifier = "Point" } },
                } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
        } } },
    } });
}

test "Parser > parse: parses fields of an anonymous structure literal" {
    const source = "val point = .{ x = 1, y = 2 };";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .StructureLiteral = .{
                .fields = .{
                    .{ .name = .{ .kind = .{ .Identifier = "x" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } } },
                    .{ .name = .{ .kind = .{ .Identifier = "y" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } } },
                },
            } } },
        } } },
    } });
}

test "Parser > parse: parses assignment to a member" {
    const source = "point.x = 3;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .Assign,
            .target = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "point" } } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 3 } } } },
        } } },
    } });
}

test "Parser > parse: parses assignment to a nested member" {
    const source = "user.location.x = 4;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .Assign,
            .target = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "user" } } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "location" } },
                } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 4 } } } },
        } } },
    } });
}

test "Parser > parse: parses assignment to an indexed element" {
    const source = "numbers[0] = 4;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .Assign,
            .target = .{ .kind = .{ .IndexExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "numbers" } } } },
                .index = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 0 } } } },
            } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 4 } } } },
        } } },
    } });
}

test "Parser > parse: parses assignment through mixed member and index access" {
    const source = "user.points[i].x = 1;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .Assign,
            .target = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .IndexExpression = .{
                    .base = .{ .kind = .{ .MemberExpression = .{
                        .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "user" } } } },
                        .member_name_token = .{ .kind = .{ .Identifier = "points" } },
                    } } },
                    .index = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "i" } } } },
                } } },
                .member_name_token = .{ .kind = .{ .Identifier = "x" } },
            } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
        } } },
    } });
}

test "Parser > parse: parses compound assignment to identifiers" {
    const source =
        \\counter += 1;
        \\balance -= 3;
        \\total *= 2;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .{ .Compound = .Add },
            .target = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "counter" } } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
        } } },
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .{ .Compound = .Subtract },
            .target = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "balance" } } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 3 } } } },
        } } },
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .{ .Compound = .Multiply },
            .target = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "total" } } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
        } } },
    } });
}

test "Parser > parse: parses compound assignment to an indexed element" {
    const source = "numbers[i] *= 2;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .AssignmentStatement = .{
            .operator = .{ .Compound = .Multiply },
            .target = .{ .kind = .{ .IndexExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "numbers" } } } },
                .index = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "i" } } } },
            } } },
            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
        } } },
    } });
}

test "Parser > parse: parses union cases without payload types" {
    const source =
        \\item Direction = union {
        \\    North,
        \\    South,
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .definition = .{ .Union = .{
                .cases = .{
                    .{ .name = .{ .kind = .{ .Identifier = "North" } }, .type_annotation = null },
                    .{ .name = .{ .kind = .{ .Identifier = "South" } }, .type_annotation = null },
                },
            } },
        } } },
    } });
}

test "Parser > parse: parses union cases with and without named payload types" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    PageUnload: unit,
        \\    KeyPress: string,
        \\    Click: Vector2D,
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .definition = .{ .Union = .{
                .cases = .{
                    .{
                        .name = .{ .kind = .{ .Identifier = "PageLoad" } },
                        .type_annotation = null,
                    },
                    .{
                        .name = .{ .kind = .{ .Identifier = "PageUnload" } },
                        .type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "unit" } } } },
                    },
                    .{
                        .name = .{ .kind = .{ .Identifier = "KeyPress" } },
                        .type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "string" } } } },
                    },
                    .{
                        .name = .{ .kind = .{ .Identifier = "Click" } },
                        .type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "Vector2D" } } } },
                    },
                },
            } },
        } } },
    } });
}

test "Parser > parse: parses function definitions inside a union" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    item asString(): string = "event";
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .definition = .{ .Union = .{
                .function_definitions = .{
                    .{ .kind = .{ .ItemDefinition = .{
                        .identifier_token = .{ .kind = .{ .Identifier = "asString" } },
                        .definition = .{ .Function = .{} },
                    } } },
                },
            } },
        } } },
    } });
}

test "Parser > parse: parses qualified union construction as a call when given a payload" {
    const source = "val event = WebEvent.KeyPress(\"A\");";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .CallExpression = .{
                .callee = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "WebEvent" } } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "KeyPress" } },
                } } },
                .arguments = .{
                    .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "A" } } } },
                },
            } } },
        } } },
    } });
}

test "Parser > parse: parses qualified union construction as member access when given no payload" {
    const source = "val event = WebEvent.PageLoad;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "WebEvent" } } } },
                .member_name_token = .{ .kind = .{ .Identifier = "PageLoad" } },
            } } },
        } } },
    } });
}

test "Parser > parse: parses an implicit member call when given a payload" {
    const source = "val event = .KeyPress(\"A\");";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .CallExpression = .{
                .callee = .{ .kind = .{ .ImplicitMemberExpression = .{
                    .member_name_token = .{ .kind = .{ .Identifier = "KeyPress" } },
                } } },
                .arguments = .{
                    .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "A" } } } },
                },
            } } },
        } } },
    } });
}

test "Parser > parse: parses an implicit member expression when given no payload" {
    const source = "val event = .PageLoad;";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const program = try parser_pipeline.parser.parse();

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .ImplicitMemberExpression = .{
                .member_name_token = .{ .kind = .{ .Identifier = "PageLoad" } },
            } } },
        } } },
    } });
}

test "Parser > parse: rejects a union when it has no cases" {
    const source = "item Empty = union {};";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const result = parser_pipeline.parser.parse();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
        .{ .severity = .@"error", .message = "union definitions must have at least one case" },
    });
}

pub const Parser = struct {
    pub const parse = struct {
        pub const match_expressions = struct {
            test "treats a bare identifier before match arms as the subject" {
                const source = "val result = match is_happy { true => 0 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const program = try parser_pipeline.parser.parse();

                try expect(program).toMatch(.{ .statements = .{
                    .{ .kind = .{ .BindingDeclaration = .{
                        .value = .{ .kind = .{ .MatchExpression = .{
                            .subject = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "is_happy" } } } },
                        } } },
                    } } },
                } });
            }

            test "allows a structure literal as a match subject when parenthesized" {
                const source = "val result = match (Point { x = 1 }) { else => 0 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const program = try parser_pipeline.parser.parse();

                try expect(program).toMatch(.{ .statements = .{
                    .{ .kind = .{ .BindingDeclaration = .{
                        .value = .{ .kind = .{ .MatchExpression = .{
                            .subject = .{ .kind = .{ .QualifiedStructureLiteral = .{
                                .structure_name = .{ .kind = .{ .Identifier = "Point" } },
                            } } },
                        } } },
                    } } },
                } });
            }

            test "parses match arms with a subject as patterns" {
                const source = "val result = match level { -1 => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const program = try parser_pipeline.parser.parse();

                try expect(program).toMatch(.{ .statements = .{
                    .{ .kind = .{ .BindingDeclaration = .{
                        .value = .{ .kind = .{ .MatchExpression = .{
                            .arms = .{
                                .{ .pattern = .{ .kind = .{ .IntegerLiteral = .{
                                    .minus_token = .{ .kind = .Minus },
                                    .literal_token = .{ .kind = .{ .IntLiteral = 1 } },
                                } } } },
                            },
                        } } },
                    } } },
                } });
            }

            test "rejects an arm after the else arm" {
                const source = "val result = match level { else => 0, 1 => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const result = parser_pipeline.parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }

            test "rejects a second else arm" {
                const source = "val result = match level { else => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const result = parser_pipeline.parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }
        };

        pub const subjectless_match_expressions = struct {
            test "parses a match without a subject with conditions as arms" {
                const source = "val result = match { level > 1 => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const program = try parser_pipeline.parser.parse();

                try expect(program).toMatch(.{ .statements = .{
                    .{ .kind = .{ .BindingDeclaration = .{
                        .value = .{ .kind = .{ .SubjectlessMatchExpression = .{
                            .arms = .{
                                .{ .condition = .{ .kind = .{ .BinaryExpression = .{ .operator = .GreaterThan } } } },
                            },
                        } } },
                    } } },
                } });
            }

            test "rejects an arm after the else arm" {
                const source = "val result = match { else => 0, level > 1 => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const result = parser_pipeline.parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }

            test "rejects a second else arm" {
                const source = "val result = match { else => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const parser_pipeline = try setupParserPipeline(&arena, source);

                const result = parser_pipeline.parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }
        };
    };
};
