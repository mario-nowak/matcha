const std = @import("std");
const expect = @import("testing").expect;
const setupPatternParserFixture = @import("testing").setupPatternParserFixture;

pub const PatternParser = struct {
    pub const parse = struct {
        pub const literals = struct {
            test "parses an integer literal pattern" {
                const source = "42";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .IntegerLiteral = .{
                    .minus_token = null,
                    .literal_token = .{ .kind = .{ .IntLiteral = 42 } },
                } } });
            }

            test "parses a minus before an integer literal as one negative integer pattern" {
                const source = "-1";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .IntegerLiteral = .{
                    .minus_token = .{ .kind = .Minus },
                    .literal_token = .{ .kind = .{ .IntLiteral = 1 } },
                } } });
            }

            test "parses a boolean literal pattern" {
                const source = "false";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .BooleanLiteral = .{ .kind = .{ .BooleanLiteral = false } } } });
            }

            test "parses a string literal pattern" {
                const source = "\"pro\"";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .StringLiteral = .{ .kind = .{ .StringLiteral = "pro" } } } });
            }
        };

        pub const cases = struct {
            test "parses an implicit case pattern without a qualifier" {
                const source = ".None";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .Case = .{
                    .qualifier_token = null,
                    .case_name_token = .{ .kind = .{ .Identifier = "None" } },
                    .binding = null,
                } } });
            }

            test "parses a qualified case pattern with the union name as qualifier" {
                const source = "Result.None";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .Case = .{
                    .qualifier_token = .{ .kind = .{ .Identifier = "Result" } },
                    .case_name_token = .{ .kind = .{ .Identifier = "None" } },
                    .binding = null,
                } } });
            }

            test "parses a payload binding in parentheses after the case name" {
                const source = ".Some(value)";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const pattern = try fixture.pattern_parser.parse();

                try expect(pattern).toMatch(.{ .kind = .{ .Case = .{
                    .case_name_token = .{ .kind = .{ .Identifier = "Some" } },
                    .binding = .{ .name_token = .{ .kind = .{ .Identifier = "value" } } },
                } } });
            }
        };

        pub const node_ids = struct {
            test "gives each parsed pattern the next node id" {
                const source = "1 2";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);
                _ = try fixture.pattern_parser.parse();

                const second_pattern = try fixture.pattern_parser.parse();

                try expect(second_pattern).toMatch(.{ .id = 1 });
            }
        };

        pub const diagnostics = struct {
            test "reports a token that starts no pattern" {
                const source = "else";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected pattern" },
                });
            }

            test "reports a minus that is not followed by an integer literal" {
                const source = "-true";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected integer literal after '-' in pattern" },
                });
            }

            test "reports a name that is not followed by a dot as a value comparison" {
                const source = "limit";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "a pattern must be a literal or a case, use a subjectless match to compare against 'limit'" },
                });
            }

            test "reports a dot that is not followed by a case name" {
                const source = ".1";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected case name after '.' in pattern" },
                });
            }

            test "reports a payload binding that is not a name" {
                const source = ".Some(1)";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected binding name in payload pattern" },
                });
            }

            test "reports a payload binding without a closing parenthesis" {
                const source = ".Some(first second)";
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupPatternParserFixture(&arena, source);

                const result = fixture.pattern_parser.parse();

                try std.testing.expectError(error.DiagnosticsEmitted, result);
                try expect(fixture.diagnostic_store.items()).toMatch(.{
                    .{ .severity = .@"error", .message = "expected ')' after payload binding" },
                });
            }
        };
    };
};
