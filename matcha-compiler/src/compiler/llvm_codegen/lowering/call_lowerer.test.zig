const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupLowererFixture = @import("testing").setupLowererFixture;

const lowering = llvm_codegen.lowering;

pub const CallLowerer = struct {
    pub const lower = struct {
        pub const user_functions = struct {
            test "lowers a call to a top-level function without receiver" {
                const source =
                    \\item identity(value: int): int = value;
                    \\val copied = identity(1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const identity_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = identity_symbol_id,
                    .receiver_node_id = null,
                } });
            }

            test "lowers a type function call without receiver" {
                const source =
                    \\item Point = structure {
                    \\    x: int;
                    \\
                    \\    item origin(): Point = Point { x = 0 };
                    \\};
                    \\val point = Point.origin();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const point_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const origin_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(point_symbol_id).kind.structure.function_symbol_ids[0];
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = origin_symbol_id,
                    .receiver_node_id = null,
                } });
            }

            test "lowers a method call with its base as receiver" {
                const source =
                    \\item Point = structure {
                    \\    x: int;
                    \\
                    \\    item moved(self: Point): Point = self;
                    \\};
                    \\val point = Point { x = 1 };
                    \\val moved = point.moved();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const point_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const moved_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(point_symbol_id).kind.structure.function_symbol_ids[0];
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[2].kind.binding_declaration.value;
                const receiver_node_id = call_expression.kind.call_expression.callee.kind.member_expression.base.id;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = moved_symbol_id,
                    .receiver_node_id = receiver_node_id,
                } });
            }

            test "lowers a union type function call without receiver" {
                const source =
                    \\item Result = union {
                    \\    None,
                    \\    Some: int,
                    \\    item fromNumber(number: int): Result = .Some(number);
                    \\};
                    \\val result = Result.fromNumber(1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const union_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const from_number_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(union_symbol_id).kind.@"union".function_symbol_ids[0];
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = from_number_symbol_id,
                    .receiver_node_id = null,
                } });
            }

            test "lowers an implicit union type function call without receiver" {
                const source =
                    \\item Result = union {
                    \\    None,
                    \\    Some: int,
                    \\    item fromNumber(number: int): Result = .Some(number);
                    \\};
                    \\val result: Result = .fromNumber(1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const union_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const from_number_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(union_symbol_id).kind.@"union".function_symbol_ids[0];
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = from_number_symbol_id,
                    .receiver_node_id = null,
                } });
            }

            test "lowers a union method call with its base as receiver" {
                const source =
                    \\item Result = union {
                    \\    None,
                    \\    Some: int,
                    \\
                    \\    item getSelf(self: Result): Result = self;
                    \\};
                    \\val result = Result.None;
                    \\val same = result.getSelf();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const union_symbol_id = fixture.analyzed_program.resolved_program.symbol_id_by_node_id.get(fixture.analyzed_program.resolved_program.program.statements[0].id).?;
                const get_self_symbol_id = fixture.analyzed_program.resolved_program.symbol_table.getSymbol(union_symbol_id).kind.@"union".function_symbol_ids[0];
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[2].kind.binding_declaration.value;
                const receiver_node_id = call_expression.kind.call_expression.callee.kind.member_expression.base.id;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .user_function = .{
                    .function_symbol_id = get_self_symbol_id,
                    .receiver_node_id = receiver_node_id,
                } });
            }
        };

        pub const builtins = struct {
            test "lowers printInt to a builtin call" {
                const source =
                    \\printInt(1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.expression_statement.expression;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .print_int });
            }

            test "lowers printString to a builtin call" {
                const source =
                    \\printString("hello");
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.expression_statement.expression;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .print_string });
            }

            test "lowers readFile to a builtin call" {
                const source =
                    \\val input = readFile("input.txt");
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .read_file });
            }

            test "lowers readLine to a builtin call" {
                const source =
                    \\val line = readLine();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .read_line });
            }

            test "lowers getArguments to a builtin call" {
                const source =
                    \\val arguments = getArguments();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .get_arguments });
            }

            test "lowers startProcess to a builtin call" {
                const source =
                    \\val output = startProcess("echo", ["hello"]);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[0].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .builtin = .start_process });
            }
        };

        pub const methods = struct {
            test "lowers trim on a string to a string method call" {
                const source =
                    \\val text = " a ";
                    \\val trimmed = text.trim();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .string_method = .trim });
            }

            test "lowers split on a string to a string method call" {
                const source =
                    \\val text = "a,b";
                    \\val parts = text.split(",");
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .string_method = .split });
            }

            test "lowers toInt on a string to a string method call" {
                const source =
                    \\val text = "1";
                    \\val number = text.toInt();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .string_method = .to_int });
            }

            test "lowers slice on a string to a string method call" {
                const source =
                    \\val text = "abc";
                    \\val part = text.slice(0, 1);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .string_method = .slice });
            }

            test "lowers toString on an integer to an integer method call" {
                const source =
                    \\val number = 1;
                    \\val text = number.toString();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.binding_declaration.value;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .integer_method = .to_string });
            }

            test "lowers append on an array to an array method call" {
                const source =
                    \\val numbers = [1];
                    \\numbers.append(2);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLowererFixture(lowering.CallLowerer, &arena, source);
                const call_expression = fixture.analyzed_program.resolved_program.program.statements[1].kind.expression_statement.expression;

                const decisions = try fixture.lowerer.lower(fixture.analyzed_program);

                try expect(decisions.get(call_expression.id).?).toMatch(.{ .array_method = .append });
            }
        };
    };
};
