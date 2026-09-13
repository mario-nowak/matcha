const std = @import("std");
const expect = @import("testing").expect;
const parse = @import("test_helpers.zig").parse;

test "parser builds the expected AST for arithmetic precedence" {
    const source =
        \\val result = 1 + 2 * 3;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .val_token = .{ .kind = .Val },
                .name = .{ .kind = .{ .Identifier = "result" } },
                .type_annotation = null,
                .binding_mutability = .Immutable,
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
        },
    });
}

test "parser respects boolean and comparison precedence" {
    const source =
        \\val result = 1 + 2 >= 3 and false or true;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "result" } },
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
        },
    });
}

test "parser binds unary not tighter than and" {
    const source =
        \\val result = not false and true;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
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
        },
    });
}

test "parser allows identifier-led trailing block expressions" {
    const source =
        \\val result = {
        \\    val left = 1;
        \\    val right = 2;
        \\    left + right
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .value = .{ .kind = .{ .Block = .{
                    .statements = .{
                        .{ .kind = .{ .BindingDeclaration = .{
                            .name = .{ .kind = .{ .Identifier = "left" } },
                            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
                        } } },
                        .{ .kind = .{ .BindingDeclaration = .{
                            .name = .{ .kind = .{ .Identifier = "right" } },
                            .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
                        } } },
                    },
                    .result = .{ .kind = .{ .BinaryExpression = .{
                        .operator = .Add,
                        .left = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "left" } } } },
                        .right = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "right" } } } },
                    } } },
                } } },
            } } },
        },
    });
}

test "parser keeps block ending with statement if as statement-only block" {
    const source =
        \\{
        \\    if true { val scoped = 1; }
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .Block = .{
                .statements = .{
                    .{ .kind = .{ .IfStatement = .{
                        .condition = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = true } } } },
                        .then_branch = .{ .kind = .{ .Block = .{
                            .statements = .{
                                .{ .kind = .{ .BindingDeclaration = .{
                                    .name = .{ .kind = .{ .Identifier = "scoped" } },
                                    .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
                                } } },
                            },
                            .result = null,
                        } } },
                    } } },
                },
                .result = null,
            } } },
        },
    });
}

test "parser treats bare identifier while conditions as conditions, not structure construction" {
    const source =
        \\while is_ready {
        \\    continue;
        \\}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .While = .{
                .condition = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "is_ready" } } } },
                .update = null,
                .body_block = .{ .kind = .{ .Block = .{
                    .statements = .{
                        .{ .kind = .{ .ContinueStatement = .{} } },
                    },
                    .result = null,
                } } },
            } } },
        },
    });
}

test "parser treats unit as a literal in expression context" {
    const source =
        \\val value = unit;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "value" } },
                .value = .{ .kind = .{ .UnitLiteral = .{ .kind = .{ .Identifier = "unit" } } } },
            } } },
        },
    });
}

test "parser treats item as a contextual definition keyword" {
    const source =
        \\val item = 1;
        \\for item in items {
        \\    printInt(item);
        \\}
        \\item Point = structure {
        \\    item: int;
        \\    item get(self: Point): int = self.item;
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "item" } },
                .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } },
            } } },
            .{ .kind = .{ .ForIn = .{
                .item_name = .{ .kind = .{ .Identifier = "item" } },
                .iterable = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "items" } } } },
                .body_block = .{ .kind = .{ .Block = .{
                    .statements = .{
                        .{ .kind = .{ .ExpressionStatement = .{
                            .expression = .{ .kind = .{ .CallExpression = .{
                                .callee = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "printInt" } } } },
                                .arguments = .{
                                    .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "item" } } } },
                                },
                            } } },
                        } } },
                    },
                    .result = null,
                } } },
            } } },
            .{ .kind = .{ .ItemDefinition = .{
                .identifier_token = .{ .kind = .{ .Identifier = "Point" } },
                .definition = .{ .Structure = .{
                    .fields = .{
                        .{
                            .name = .{ .kind = .{ .Identifier = "item" } },
                            .type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "int" } } } },
                        },
                    },
                    .function_definitions = .{
                        .{ .kind = .{ .ItemDefinition = .{
                            .identifier_token = .{ .kind = .{ .Identifier = "get" } },
                            .definition = .{ .Function = .{
                                .parameters = .{
                                    .{
                                        .name = .{ .kind = .{ .Identifier = "self" } },
                                        .type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "Point" } } } },
                                    },
                                },
                                .return_type_annotation = .{ .Named = .{ .name_token = .{ .kind = .{ .Identifier = "int" } } } },
                                .body_expression = .{ .kind = .{ .MemberExpression = .{
                                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "self" } } } },
                                    .member_name_token = .{ .kind = .{ .Identifier = "item" } },
                                } } },
                            } },
                        } } },
                    },
                } },
            } } },
        },
    });
}

test "parser parses structure member access expressions" {
    const source =
        \\val x = point.x;
        \\val y = user.location.x;
        \\val z = (Point { x = 1, y = 2 }).x;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "x" } },
                .value = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "point" } } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "x" } },
                } } },
            } } },
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "y" } },
                .value = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .MemberExpression = .{
                        .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "user" } } } },
                        .member_name_token = .{ .kind = .{ .Identifier = "location" } },
                    } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "x" } },
                } } },
            } } },
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "z" } },
                .value = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .QualifiedStructureLiteral = .{
                        .structure_name = .{ .kind = .{ .Identifier = "Point" } },
                        .fields = .{
                            .{ .name = .{ .kind = .{ .Identifier = "x" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } } },
                            .{ .name = .{ .kind = .{ .Identifier = "y" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } } },
                        },
                    } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "x" } },
                } } },
            } } },
        },
    });
}

test "parser parses anonymous structure literal expressions" {
    const source =
        \\val point = .{ x = 1, y = 2 };
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .name = .{ .kind = .{ .Identifier = "point" } },
                .value = .{ .kind = .{ .StructureLiteral = .{
                    .fields = .{
                        .{ .name = .{ .kind = .{ .Identifier = "x" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } } },
                        .{ .name = .{ .kind = .{ .Identifier = "y" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } } },
                    },
                } } },
            } } },
        },
    });
}

test "parser parses structure member assignment statements" {
    const source =
        \\point.x = 3;
        \\user.location.x = 4;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .AssignmentStatement = .{
                .operator = .Assign,
                .target = .{ .kind = .{ .MemberExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "point" } } } },
                    .member_name_token = .{ .kind = .{ .Identifier = "x" } },
                } } },
                .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 3 } } } },
            } } },
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
        },
    });
}

test "parser parses indexed and mixed place assignment statements" {
    const source =
        \\numbers[0] = 4;
        \\user.points[i].x = 1;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .AssignmentStatement = .{
                .operator = .Assign,
                .target = .{ .kind = .{ .IndexExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "numbers" } } } },
                    .index = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 0 } } } },
                } } },
                .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 4 } } } },
            } } },
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
        },
    });
}

test "parser parses compound assignment statements as assignment nodes with compound operators" {
    const source =
        \\counter += 1;
        \\balance -= 3;
        \\numbers[i] *= 2;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
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
                .target = .{ .kind = .{ .IndexExpression = .{
                    .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "numbers" } } } },
                    .index = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "i" } } } },
                } } },
                .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } },
            } } },
        },
    });
}

test "parser treats bare identifier match subjects as subjects, not structure construction" {
    const source =
        \\val message = match is_happy {
        \\    true => "yes",
        \\    false => "no",
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .value = .{ .kind = .{ .MatchExpression = .{
                    .subject = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "is_happy" } } } },
                    .arms = .{
                        .{
                            .pattern_or_condition = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = true } } } },
                            .body = .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "yes" } } } },
                        },
                        .{
                            .pattern_or_condition = .{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = false } } } },
                            .body = .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "no" } } } },
                        },
                    },
                    .else_arm = null,
                } } },
            } } },
        },
    });
}

test "parser allows parenthesized structure construction as a match subject" {
    const source =
        \\val result = match (Point { x = 1, y = 2 }) {
        \\    else => 0,
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{
        .statements = .{
            .{ .kind = .{ .BindingDeclaration = .{
                .value = .{ .kind = .{ .MatchExpression = .{
                    .subject = .{ .kind = .{ .QualifiedStructureLiteral = .{
                        .structure_name = .{ .kind = .{ .Identifier = "Point" } },
                        .fields = .{
                            .{ .name = .{ .kind = .{ .Identifier = "x" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 1 } } } } },
                            .{ .name = .{ .kind = .{ .Identifier = "y" } }, .value = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 2 } } } } },
                        },
                    } } },
                    .arms = .{},
                    .else_arm = .{ .kind = .{ .IntegerLiteral = .{ .kind = .{ .IntLiteral = 0 } } } },
                } } },
            } } },
        },
    });
}

test "parser parses union definitions with cases without type annotations" {
    const source =
        \\item Direction = union {
        \\    North,
        \\    South,
        \\    East,
        \\    West,
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "Direction" } },
            .definition = .{
                .Union = .{
                    .cases = .{
                        .{
                            .name = .{ .kind = .{ .Identifier = "North" } },
                            .type_annotation = null,
                        },
                        .{
                            .name = .{ .kind = .{ .Identifier = "South" } },
                            .type_annotation = null,
                        },
                        .{
                            .name = .{ .kind = .{ .Identifier = "East" } },
                            .type_annotation = null,
                        },
                        .{
                            .name = .{ .kind = .{ .Identifier = "West" } },
                            .type_annotation = null,
                        },
                    },
                },
            },
        } } },
    } });
}

test "parser parses union definitions with cases with type annotations" {
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

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{
                .Union = .{
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
                },
            },
        } } },
    } });
}

test "parser parses union definitions with function definitions" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    KeyPress: string,
        \\    Click: Vector2D,
        \\
        \\    item asString(self: WebEvent): string = match (self) {
        \\        .PageLoad => "Page Load",
        \\        .KeyPress(key) => "Key Press: " + key,
        \\        .Click(vector2D) => vector2D.asString(),
        \\    };
        \\};
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{
                .Union = .{
                    .function_definitions = .{
                        .{ .kind = .{ .ItemDefinition = .{
                            .identifier_token = .{ .kind = .{ .Identifier = "asString" } },
                            .definition = .{ .Function = .{} },
                        } } },
                    },
                },
            },
        } } },
    } });
}

test "parser parses qualified union construction with a value as call expression on a member expression" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    KeyPress: string,
        \\};
        \\val event = WebEvent.KeyPress("A");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{ .Union = .{} },
        } } },
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .CallExpression = .{
                .callee = .{ .kind = .{
                    .MemberExpression = .{
                        .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "WebEvent" } } } },
                        .member_name_token = .{ .kind = .{ .Identifier = "KeyPress" } },
                    },
                } },
                .arguments = .{
                    .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "A" } } } },
                },
            } } },
        } } },
    } });
}

test "parser parses qualified union construction without a value as a member expression" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    KeyPress: string,
        \\};
        \\val event = WebEvent.PageLoad;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{ .Union = .{} },
        } } },
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .MemberExpression = .{
                .base = .{ .kind = .{ .Identifier = .{ .kind = .{ .Identifier = "WebEvent" } } } },
                .member_name_token = .{ .kind = .{ .Identifier = "PageLoad" } },
            } } },
        } } },
    } });
}

test "parser parses contextual union construction with a value as call expression on an implicit member expression" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    KeyPress: string,
        \\};
        \\val event: WebEvent = .KeyPress("A");
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{ .Union = .{} },
        } } },
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .CallExpression = .{
                .callee = .{ .kind = .{
                    .ImplicitMemberExpression = .{
                        .member_name_token = .{ .kind = .{ .Identifier = "KeyPress" } },
                    },
                } },
                .arguments = .{
                    .{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "A" } } } },
                },
            } } },
        } } },
    } });
}

test "parser parses contextual union construction without a value as an implicit member expression" {
    const source =
        \\item WebEvent = union {
        \\    PageLoad,
        \\    KeyPress: string,
        \\};
        \\val event: WebEvent = .PageLoad;
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parse(arena.allocator(), source);

    try expect(program).toMatch(.{ .statements = .{
        .{ .kind = .{ .ItemDefinition = .{
            .identifier_token = .{ .kind = .{ .Identifier = "WebEvent" } },
            .definition = .{ .Union = .{} },
        } } },
        .{ .kind = .{ .BindingDeclaration = .{
            .value = .{ .kind = .{ .ImplicitMemberExpression = .{
                .member_name_token = .{ .kind = .{ .Identifier = "PageLoad" } },
            } } },
        } } },
    } });
}
