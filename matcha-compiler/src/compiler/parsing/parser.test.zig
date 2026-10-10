const std = @import("std");
const parsing = @import("parsing");
const expect = @import("testing").expect;
const setupParserFixture = @import("testing").setupParserFixture;
const setupLexerPipeline = @import("testing").setupLexerPipeline;

pub const Parser = struct {
    pub const parse = struct {
        pub const operator_precedence = struct {
            test "binds multiplication tighter than addition" {
                const source = "val result = 1 + 2 * 3;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .binary_expression = .{
                            .operator = .add,
                            .left = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } },
                            .right = .{ .kind = .{ .binary_expression = .{
                                .operator = .multiply,
                                .left = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } },
                                .right = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 3 } } } },
                            } } },
                        } } },
                    } } },
                } });
            }

            test "orders arithmetic, comparison, and boolean operators by precedence" {
                const source = "val result = 1 + 2 >= 3 and false or true;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .binary_expression = .{
                            .operator = .@"or",
                            .left = .{ .kind = .{ .binary_expression = .{
                                .operator = .@"and",
                                .left = .{ .kind = .{ .binary_expression = .{
                                    .operator = .greater_than_or_equal,
                                    .left = .{ .kind = .{ .binary_expression = .{
                                        .operator = .add,
                                        .left = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } },
                                        .right = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } },
                                    } } },
                                    .right = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 3 } } } },
                                } } },
                                .right = .{ .kind = .{ .boolean_literal = .{ .kind = .{ .boolean_literal = false } } } },
                            } } },
                            .right = .{ .kind = .{ .boolean_literal = .{ .kind = .{ .boolean_literal = true } } } },
                        } } },
                    } } },
                } });
            }

            test "binds unary not tighter than and" {
                const source = "val result = not false and true;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .binary_expression = .{
                            .operator = .@"and",
                            .left = .{ .kind = .{ .unary_expression = .{
                                .operator = .not,
                                .operand = .{ .kind = .{ .boolean_literal = .{ .kind = .{ .boolean_literal = false } } } },
                            } } },
                            .right = .{ .kind = .{ .boolean_literal = .{ .kind = .{ .boolean_literal = true } } } },
                        } } },
                    } } },
                } });
            }
        };

        pub const blocks = struct {
            test "allows an identifier-led block result after statements" {
                const source =
                    \\val result = {
                    \\    val left = 1;
                    \\    left + right
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .block = .{
                            .statements = .{
                                .{ .kind = .{ .binding_declaration = .{} } },
                            },
                            .result = .{ .kind = .{ .binary_expression = .{
                                .operator = .add,
                                .left = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "left" } } } },
                                .right = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "right" } } } },
                            } } },
                        } } },
                    } } },
                } });
            }

            test "keeps a block statement-only when it ends with an if statement" {
                const source =
                    \\{
                    \\    if true { val scoped = 1; }
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .block = .{
                        .statements = .{
                            .{ .kind = .{ .if_statement = .{} } },
                        },
                        .result = null,
                    } } },
                } });
            }
        };

        pub const while_loops = struct {
            test "treats a bare identifier before a while body as the condition" {
                const source = "while is_ready { continue; }";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .@"while" = .{
                        .condition = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "is_ready" } } } },
                    } } },
                } });
            }
        };

        pub const literals = struct {
            test "treats unit as a literal when used as an expression" {
                const source = "val value = unit;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .unit_literal = .{} } },
                    } } },
                } });
            }
        };

        pub const item_keyword = struct {
            test "allows item as a binding name" {
                const source = "val item = 1;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .name = .{ .kind = .{ .identifier = "item" } },
                    } } },
                } });
            }

            test "allows item as a for-in binding name" {
                const source = "for item in items { continue; }";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .for_in = .{
                        .item_name = .{ .kind = .{ .identifier = "item" } },
                    } } },
                } });
            }

            test "allows item as an identifier expression" {
                const source = "val value = item;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "item" } } } },
                    } } },
                } });
            }

            test "allows item as a structure field name" {
                const source = "item Point = structure { item: int; };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .definition = .{ .structure = .{
                            .fields = .{
                                .{ .name = .{ .kind = .{ .identifier = "item" } } },
                            },
                        } },
                    } } },
                } });
            }

            test "allows item as a member name" {
                const source = "val value = point.item;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .member_expression = .{
                            .member_name_token = .{ .kind = .{ .identifier = "item" } },
                        } } },
                    } } },
                } });
            }

            test "recognizes item as a structure definition keyword" {
                const source = "item Point = structure { x: int; };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .identifier_token = .{ .kind = .{ .identifier = "Point" } },
                        .definition = .{ .structure = .{} },
                    } } },
                } });
            }

            test "recognizes item as a function definition keyword inside a structure" {
                const source =
                    \\item Point = structure {
                    \\    item get(self: Point): int = 1;
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .definition = .{ .structure = .{
                            .function_definitions = .{
                                .{ .kind = .{ .item_definition = .{
                                    .identifier_token = .{ .kind = .{ .identifier = "get" } },
                                    .definition = .{ .function = .{} },
                                } } },
                            },
                        } },
                    } } },
                } });
            }
        };

        pub const member_access = struct {
            test "parses member access on an identifier" {
                const source = "val value = point.x;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "point" } } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                    } } },
                } });
            }

            test "parses nested member access" {
                const source = "val value = user.location.x;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .member_expression = .{
                                .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "user" } } } },
                                .member_name_token = .{ .kind = .{ .identifier = "location" } },
                            } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                    } } },
                } });
            }

            test "parses member access on a parenthesized structure literal" {
                const source = "val value = (Point { x = 1 }).x;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .qualified_structure_literal = .{
                                .structure_name = .{ .kind = .{ .identifier = "Point" } },
                            } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                    } } },
                } });
            }
        };

        pub const structure_literals = struct {
            test "parses fields of an anonymous structure literal" {
                const source = "val point = .{ x = 1, y = 2 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .structure_literal = .{
                            .fields = .{
                                .{ .name = .{ .kind = .{ .identifier = "x" } }, .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } } },
                                .{ .name = .{ .kind = .{ .identifier = "y" } }, .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } } },
                            },
                        } } },
                    } } },
                } });
            }
        };

        pub const assignments = struct {
            test "parses assignment to a member" {
                const source = "point.x = 3;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .assign,
                        .target = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "point" } } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 3 } } } },
                    } } },
                } });
            }

            test "parses assignment to a nested member" {
                const source = "user.location.x = 4;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .assign,
                        .target = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .member_expression = .{
                                .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "user" } } } },
                                .member_name_token = .{ .kind = .{ .identifier = "location" } },
                            } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 4 } } } },
                    } } },
                } });
            }

            test "parses assignment to an indexed element" {
                const source = "numbers[0] = 4;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .assign,
                        .target = .{ .kind = .{ .index_expression = .{
                            .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "numbers" } } } },
                            .index = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 0 } } } },
                        } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 4 } } } },
                    } } },
                } });
            }

            test "parses assignment through mixed member and index access" {
                const source = "user.points[i].x = 1;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .assign,
                        .target = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .index_expression = .{
                                .base = .{ .kind = .{ .member_expression = .{
                                    .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "user" } } } },
                                    .member_name_token = .{ .kind = .{ .identifier = "points" } },
                                } } },
                                .index = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "i" } } } },
                            } } },
                            .member_name_token = .{ .kind = .{ .identifier = "x" } },
                        } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } },
                    } } },
                } });
            }

            test "parses compound assignment to identifiers" {
                const source =
                    \\counter += 1;
                    \\balance -= 3;
                    \\total *= 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .{ .compound = .add },
                        .target = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "counter" } } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } },
                    } } },
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .{ .compound = .subtract },
                        .target = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "balance" } } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 3 } } } },
                    } } },
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .{ .compound = .multiply },
                        .target = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "total" } } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } },
                    } } },
                } });
            }

            test "parses compound assignment to an indexed element" {
                const source = "numbers[i] *= 2;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .assignment_statement = .{
                        .operator = .{ .compound = .multiply },
                        .target = .{ .kind = .{ .index_expression = .{
                            .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "numbers" } } } },
                            .index = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "i" } } } },
                        } } },
                        .value = .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } },
                    } } },
                } });
            }
        };

        pub const union_definitions = struct {
            test "parses union cases without payload types" {
                const source =
                    \\item Direction = union {
                    \\    North,
                    \\    South,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .definition = .{ .@"union" = .{
                            .cases = .{
                                .{ .name = .{ .kind = .{ .identifier = "North" } }, .type_annotation = null },
                                .{ .name = .{ .kind = .{ .identifier = "South" } }, .type_annotation = null },
                            },
                        } },
                    } } },
                } });
            }

            test "parses union cases with and without named payload types" {
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
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .definition = .{ .@"union" = .{
                            .cases = .{
                                .{
                                    .name = .{ .kind = .{ .identifier = "PageLoad" } },
                                    .type_annotation = null,
                                },
                                .{
                                    .name = .{ .kind = .{ .identifier = "PageUnload" } },
                                    .type_annotation = .{ .named = .{ .name_token = .{ .kind = .{ .identifier = "unit" } } } },
                                },
                                .{
                                    .name = .{ .kind = .{ .identifier = "KeyPress" } },
                                    .type_annotation = .{ .named = .{ .name_token = .{ .kind = .{ .identifier = "string" } } } },
                                },
                                .{
                                    .name = .{ .kind = .{ .identifier = "Click" } },
                                    .type_annotation = .{ .named = .{ .name_token = .{ .kind = .{ .identifier = "Vector2D" } } } },
                                },
                            },
                        } },
                    } } },
                } });
            }

            test "parses function definitions inside a union" {
                const source =
                    \\item WebEvent = union {
                    \\    PageLoad,
                    \\    item asString(): string = "event";
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .item_definition = .{
                        .definition = .{ .@"union" = .{
                            .function_definitions = .{
                                .{ .kind = .{ .item_definition = .{
                                    .identifier_token = .{ .kind = .{ .identifier = "asString" } },
                                    .definition = .{ .function = .{} },
                                } } },
                            },
                        } },
                    } } },
                } });
            }

            test "rejects a union when it has no cases" {
                const source = "item Empty = union {};";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "union definitions must have at least one case" },
                });
            }
        };

        pub const union_construction = struct {
            test "parses qualified union construction as a call when given a payload" {
                const source = "val event = WebEvent.KeyPress(\"A\");";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .call_expression = .{
                            .callee = .{ .kind = .{ .member_expression = .{
                                .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "WebEvent" } } } },
                                .member_name_token = .{ .kind = .{ .identifier = "KeyPress" } },
                            } } },
                            .arguments = .{
                                .{ .kind = .{ .string_literal = .{ .kind = .{ .string_literal = "A" } } } },
                            },
                        } } },
                    } } },
                } });
            }

            test "parses qualified union construction as member access when given no payload" {
                const source = "val event = WebEvent.PageLoad;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .member_expression = .{
                            .base = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "WebEvent" } } } },
                            .member_name_token = .{ .kind = .{ .identifier = "PageLoad" } },
                        } } },
                    } } },
                } });
            }

            test "parses an implicit member call when given a payload" {
                const source = "val event = .KeyPress(\"A\");";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .call_expression = .{
                            .callee = .{ .kind = .{ .implicit_member_expression = .{
                                .member_name_token = .{ .kind = .{ .identifier = "KeyPress" } },
                            } } },
                            .arguments = .{
                                .{ .kind = .{ .string_literal = .{ .kind = .{ .string_literal = "A" } } } },
                            },
                        } } },
                    } } },
                } });
            }

            test "parses an implicit member expression when given no payload" {
                const source = "val event = .PageLoad;";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .implicit_member_expression = .{
                            .member_name_token = .{ .kind = .{ .identifier = "PageLoad" } },
                        } } },
                    } } },
                } });
            }
        };

        pub const match_expressions = struct {
            test "treats a bare identifier before match arms as the subject" {
                const source = "val result = match is_happy { true => 0 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .match_expression = .{
                            .subject = .{ .kind = .{ .identifier = .{ .kind = .{ .identifier = "is_happy" } } } },
                        } } },
                    } } },
                } });
            }

            test "allows a structure literal as a match subject when parenthesized" {
                const source = "val result = match (Point { x = 1 }) { else => 0 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .match_expression = .{
                            .subject = .{ .kind = .{ .qualified_structure_literal = .{
                                .structure_name = .{ .kind = .{ .identifier = "Point" } },
                            } } },
                        } } },
                    } } },
                } });
            }

            test "parses match arms with a subject as patterns" {
                const source = "val result = match level { -1 => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .match_expression = .{
                            .arms = .{
                                .{ .pattern = .{ .kind = .{ .integer_literal = .{
                                    .minus_token = .{ .kind = .minus },
                                    .literal_token = .{ .kind = .{ .int_literal = 1 } },
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
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }

            test "rejects a second else arm" {
                const source = "val result = match level { else => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }
        };

        pub const subjectless_match_expressions = struct {
            test "parses a match without a subject with conditions as arms" {
                const source = "val result = match { level > 1 => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .subjectless_match_expression = .{
                            .arms = .{
                                .{ .condition = .{ .kind = .{ .binary_expression = .{ .operator = .greater_than } } } },
                            },
                        } } },
                    } } },
                } });
            }

            test "rejects an arm after the else arm" {
                const source = "val result = match { else => 0, level > 1 => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }

            test "rejects a second else arm" {
                const source = "val result = match { else => 0, else => 1 };";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "'else' must be the last match arm" },
                });
            }
        };

        pub const call_expressions = struct {
            test "rejects arguments without a comma between them" {
                const source = "val sum = add(1 2);";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected ',' or ')' after call argument" },
                });
            }

            test "rejects a comma before the first argument" {
                const source = "val sum = add(, 1);";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected expression" },
                });
            }

            test "rejects two commas between arguments" {
                const source = "val sum = add(1,, 2);";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const result = fixture.parser.parse(fixture.lexer.*);

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected expression" },
                });
            }

            test "accepts a trailing comma after the last argument" {
                const source = "val sum = add(1, 2,);";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupParserFixture(&arena, source);

                const module = try fixture.parser.parse(fixture.lexer.*);

                try expect(module).toMatch(.{ .statements = .{
                    .{ .kind = .{ .binding_declaration = .{
                        .value = .{ .kind = .{ .call_expression = .{
                            .arguments = .{
                                .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 1 } } } },
                                .{ .kind = .{ .integer_literal = .{ .kind = .{ .int_literal = 2 } } } },
                            },
                        } } },
                    } } },
                } });
            }
        };

        test "gives different node ids to modules parsed by one parser" {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const first_lexer_pipeline = try setupLexerPipeline(&arena, "val first = 1;");
            const second_lexer_pipeline = try setupLexerPipeline(&arena, "val second = 2;");
            var parser = parsing.Parser.init(arena.allocator(), first_lexer_pipeline.diagnostic_store);
            const first_module = try parser.parse(first_lexer_pipeline.lexer.*);

            const second_module = try parser.parse(second_lexer_pipeline.lexer.*);

            try std.testing.expect(second_module.statements[0].id != first_module.statements[0].id);
        }
    };
};
