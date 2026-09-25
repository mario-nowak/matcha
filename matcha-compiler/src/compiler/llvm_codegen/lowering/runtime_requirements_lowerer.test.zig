const std = @import("std");
const llvm_codegen = @import("llvm_codegen");
const expect = @import("testing").expect;
const setupRuntimeRequirementsLowererFixture = @import("testing").setupRuntimeRequirementsLowererFixture;

const RuntimeRequirementsPlan = llvm_codegen.lowering.lowering_types.RuntimeRequirementsPlan;

pub const RuntimeRequirementsLowerer = struct {
    pub const lower = struct {
        test "requires no runtime functions when the program makes no runtime calls" {
            const source =
                \\val answer = 41 + 1;
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(RuntimeRequirementsPlan{});
        }

        test "requires print int when printInt is called" {
            const source =
                \\printInt(1);
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .print_int = true });
        }

        test "requires print string when printString is called" {
            const source =
                \\printString("hello");
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .print_string = true });
        }

        test "requires read file when readFile is called" {
            const source =
                \\val input = readFile("input.txt");
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .read_file = true });
        }

        test "requires read line when readLine is called" {
            const source =
                \\val line = readLine();
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .read_line = true });
        }

        test "requires get arguments when getArguments is called" {
            const source =
                \\val arguments = getArguments();
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .get_arguments = true });
        }

        test "requires string trim when trim is called on a string" {
            const source =
                \\val text = " value ";
                \\val trimmed = text.trim();
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_trim = true });
        }

        test "requires string split when split is called on a string" {
            const source =
                \\val text = "a,b";
                \\val parts = text.split(",");
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_split = true });
        }

        test "requires string to int when toInt is called on a string" {
            const source =
                \\val text = "42";
                \\val number = text.toInt();
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_to_int = true });
        }

        test "requires int to string when toString is called on an integer" {
            const source =
                \\val number = 42;
                \\val text = number.toString();
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .int_to_string = true });
        }

        test "requires array append slot when append is called on an array" {
            const source =
                \\val numbers = [1];
                \\numbers.append(2);
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .array_append_slot = true });
        }

        test "requires the index out of bounds panic when an array is indexed" {
            const source =
                \\val numbers = [1];
                \\val first = numbers[0];
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .panic_index_out_of_bounds = true });
        }

        test "requires string concatenate when strings are added" {
            const source =
                \\val text = "a" + "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_concatenate = true });
        }

        test "requires string concatenate when a string is compound assigned with addition" {
            const source =
                \\var text = "a";
                \\text += "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_concatenate = true });
        }

        test "requires string compare when strings are compared for equality" {
            const source =
                \\val same = "a" == "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_compare = true });
        }

        test "requires string compare when strings are compared for inequality" {
            const source =
                \\val different = "a" != "b";
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_compare = true });
        }

        test "requires string compare when a match has a string subject" {
            const source =
                \\val score = match "pro" {
                \\    "pro" => 1,
                \\    else => 0,
                \\};
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .string_compare = true });
        }

        test "requires a runtime function that is only called inside a function definition" {
            const source =
                \\item log(): unit = printInt(1);
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .print_int = true });
        }

        test "requires a runtime function that is only called inside a structure method" {
            const source =
                \\item Logger = structure {
                \\    value: int;
                \\
                \\    item log(): unit = printInt(1);
                \\};
            ;
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const fixture = try setupRuntimeRequirementsLowererFixture(&arena, source);

            const plan = fixture.runtime_requirements_lowerer.lower(fixture.analyzed_program);

            try expect(plan).toMatch(.{ .print_int = true });
        }
    };
};
