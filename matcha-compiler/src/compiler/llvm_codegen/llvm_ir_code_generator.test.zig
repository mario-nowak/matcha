const std = @import("std");
const expect = @import("testing").expect;
const setupLlvmIrCodeGeneratorFixture = @import("testing").setupLlvmIrCodeGeneratorFixture;

pub const LlvmIrCodeGenerator = struct {
    pub const generateLlvmIr = struct {
        pub const structures = struct {
            test "lowers a structure passed to a function and printed" {
                const source =
                    \\item Point = structure { x: int; y: int; };
                    \\item sum(point: Point): int = point.x + point.y;
                    \\printInt(sum(Point { x = 1, y = 2 }));
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_print_int(i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\%matcha_structure_0_Point = type { i64, i64 }
                    \\
                    \\define i64 @matcha_function_1_sum(ptr %arg_0_point) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    store ptr %arg_0_point, ptr %.s_0
                    \\    %.t_0 = load ptr, ptr %.s_0
                    \\    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
                    \\    %.t_2 = load i64, ptr %.t_1
                    \\    %.t_3 = load ptr, ptr %.s_0
                    \\    %.t_4 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 1
                    \\    %.t_5 = load i64, ptr %.t_4
                    \\    %.t_6 = add i64 %.t_2, %.t_5
                    \\    ret i64 %.t_6
                    \\}
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
                    \\    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
                    \\    store i64 1, ptr %.t_1
                    \\    %.t_2 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1
                    \\    store i64 2, ptr %.t_2
                    \\    %.t_3 = call i64 @matcha_function_1_sum(ptr %.t_0)
                    \\    call void @matcha_print_int(i64 %.t_3)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const control_flow = struct {
            test "lowers an if expression with values to branches and a phi" {
                const source =
                    \\val flag = true;
                    \\val score = if flag { 2 } else { 1 };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i1
                    \\    %.s_1 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    store i1 1, ptr %.s_0
                    \\    %.t_0 = load i1, ptr %.s_0
                    \\    br i1 %.t_0, label %label_then_2, label %label_else_1
                    \\label_then_2:
                    \\    br label %label_continue_0
                    \\label_else_1:
                    \\    br label %label_continue_0
                    \\label_continue_0:
                    \\    %.t_1 = phi i64 [2, %label_then_2], [1, %label_else_1]
                    \\    store i64 %.t_1, ptr %.s_1
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers an if expression without a value to branches without a phi" {
                const source =
                    \\if true { val left = 1; } else { val right = 2; };
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    %.s_1 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    br i1 1, label %label_then_2, label %label_else_1
                    \\label_then_2:
                    \\    store i64 1, ptr %.s_0
                    \\    br label %label_continue_0
                    \\label_else_1:
                    \\    store i64 2, ptr %.s_1
                    \\    br label %label_continue_0
                    \\label_continue_0:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "branches to the continue block when a statement if has no else" {
                const source =
                    \\if true { val value = 1; }
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    br i1 1, label %label_then_1, label %label_continue_0
                    \\label_then_1:
                    \\    store i64 1, ptr %.s_0
                    \\    br label %label_continue_0
                    \\label_continue_0:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "routes continue in a while loop through the update clause" {
                const source =
                    \\var index = 0;
                    \\while index < 5 : index = index + 1 {
                    \\    continue;
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    store i64 0, ptr %.s_0
                    \\    br label %label_loop_header_0
                    \\label_loop_header_0:
                    \\    %.t_0 = load i64, ptr %.s_0
                    \\    %.t_1 = icmp slt i64 %.t_0, 5
                    \\    br i1 %.t_1, label %label_loop_body_1, label %label_loop_exit_3
                    \\label_loop_body_1:
                    \\    br label %label_loop_continue_2
                    \\label_loop_continue_2:
                    \\    %.t_2 = load i64, ptr %.s_0
                    \\    %.t_3 = add i64 %.t_2, 1
                    \\    store i64 %.t_3, ptr %.s_0
                    \\    br label %label_loop_header_0
                    \\label_loop_exit_3:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers boolean operators and comparisons" {
                const source =
                    \\val negated = not false;
                    \\val both = negated and true;
                    \\val greater = 2 >= 1;
                    \\val same = true == false;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i1
                    \\    %.s_1 = alloca i1
                    \\    %.s_2 = alloca i1
                    \\    %.s_3 = alloca i1
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = xor i1 0, 1
                    \\    store i1 %.t_0, ptr %.s_0
                    \\    %.t_1 = load i1, ptr %.s_0
                    \\    %.t_2 = and i1 %.t_1, 1
                    \\    store i1 %.t_2, ptr %.s_1
                    \\    %.t_3 = icmp sge i64 2, 1
                    \\    store i1 %.t_3, ptr %.s_2
                    \\    %.t_4 = icmp eq i1 1, 0
                    \\    store i1 %.t_4, ptr %.s_3
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const match = struct {
            test "lowers a match with a subject to a compare and branch chain" {
                const source =
                    \\val score = match 2 {
                    \\    1 => 10,
                    \\    2 => 20,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = icmp eq i64 2, 1
                    \\    br i1 %.t_0, label %label_match_arm_2, label %label_match_next_3
                    \\label_match_arm_2:
                    \\    br label %label_match_continue_0
                    \\label_match_next_3:
                    \\    %.t_1 = icmp eq i64 2, 2
                    \\    br i1 %.t_1, label %label_match_arm_4, label %label_match_else_1
                    \\label_match_arm_4:
                    \\    br label %label_match_continue_0
                    \\label_match_else_1:
                    \\    br label %label_match_continue_0
                    \\label_match_continue_0:
                    \\    %.t_2 = phi i64 [10, %label_match_arm_2], [20, %label_match_arm_4], [0, %label_match_else_1]
                    \\    store i64 %.t_2, ptr %.s_0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers a match without a subject to condition branches" {
                const source =
                    \\val flag = true;
                    \\val score = match {
                    \\    flag => 1,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i1
                    \\    %.s_1 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    store i1 1, ptr %.s_0
                    \\    %.t_0 = load i1, ptr %.s_0
                    \\    br i1 %.t_0, label %label_match_arm_2, label %label_match_else_1
                    \\label_match_arm_2:
                    \\    br label %label_match_continue_0
                    \\label_match_else_1:
                    \\    br label %label_match_continue_0
                    \\label_match_continue_0:
                    \\    %.t_1 = phi i64 [1, %label_match_arm_2], [0, %label_match_else_1]
                    \\    store i64 %.t_1, ptr %.s_1
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "compares a string match subject with the runtime string compare" {
                const source =
                    \\val score = match "pro" {
                    \\    "pro" => 1,
                    \\    else => 0,
                    \\};
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare i1 @matcha_string_compare(ptr, i64, ptr, i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\@.string_literal_0 = private unnamed_addr constant [3 x i8] c"pro"
                    \\@.string_literal_1 = private unnamed_addr constant [3 x i8] c"pro"
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = getelementptr inbounds [3 x i8], ptr @.string_literal_0, i64 0, i64 0
                    \\    %.t_1 = insertvalue %String undef, ptr %.t_0, 0
                    \\    %.t_2 = insertvalue %String %.t_1, i64 3, 1
                    \\    %.t_3 = getelementptr inbounds [3 x i8], ptr @.string_literal_1, i64 0, i64 0
                    \\    %.t_4 = insertvalue %String undef, ptr %.t_3, 0
                    \\    %.t_5 = insertvalue %String %.t_4, i64 3, 1
                    \\    %.t_6 = extractvalue %String %.t_2, 0
                    \\    %.t_7 = extractvalue %String %.t_2, 1
                    \\    %.t_8 = extractvalue %String %.t_5, 0
                    \\    %.t_9 = extractvalue %String %.t_5, 1
                    \\    %.t_10 = call i1 @matcha_string_compare(ptr %.t_6, i64 %.t_7, ptr %.t_8, i64 %.t_9)
                    \\    br i1 %.t_10, label %label_match_arm_2, label %label_match_else_1
                    \\label_match_arm_2:
                    \\    br label %label_match_continue_0
                    \\label_match_else_1:
                    \\    br label %label_match_continue_0
                    \\label_match_continue_0:
                    \\    %.t_11 = phi i64 [1, %label_match_arm_2], [0, %label_match_else_1]
                    \\    store i64 %.t_11, ptr %.s_0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const arrays = struct {
            test "lowers an array literal and a for in loop over it" {
                const source =
                    \\val numbers = [1, 2];
                    \\for value in numbers {
                    \\    printInt(value);
                    \\}
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_print_int(i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    %.s_1 = alloca i64
                    \\    %.s_2 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
                    \\    %.t_1 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 2) to i64))
                    \\    %.t_2 = getelementptr inbounds i64, ptr %.t_1, i64 0
                    \\    store i64 1, ptr %.t_2
                    \\    %.t_3 = getelementptr inbounds i64, ptr %.t_1, i64 1
                    \\    store i64 2, ptr %.t_3
                    \\    %.t_4 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
                    \\    store i64 2, ptr %.t_4
                    \\    %.t_5 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 1
                    \\    store i64 2, ptr %.t_5
                    \\    %.t_6 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 2
                    \\    store ptr %.t_1, ptr %.t_6
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    %.t_7 = load ptr, ptr %.s_0
                    \\    store i64 0, ptr %.s_2
                    \\    %.t_8 = getelementptr inbounds %Array, ptr %.t_7, i32 0, i32 0
                    \\    %.t_9 = load i64, ptr %.t_8
                    \\    %.t_10 = getelementptr inbounds %Array, ptr %.t_7, i32 0, i32 2
                    \\    %.t_11 = load ptr, ptr %.t_10
                    \\    br label %label_loop_header_0
                    \\label_loop_header_0:
                    \\    %.t_12 = load i64, ptr %.s_2
                    \\    %.t_13 = icmp slt i64 %.t_12, %.t_9
                    \\    br i1 %.t_13, label %label_loop_body_1, label %label_loop_exit_3
                    \\label_loop_body_1:
                    \\    %.t_14 = getelementptr inbounds i64, ptr %.t_11, i64 %.t_12
                    \\    %.t_15 = load i64, ptr %.t_14
                    \\    store i64 %.t_15, ptr %.s_1
                    \\    %.t_16 = load i64, ptr %.s_1
                    \\    call void @matcha_print_int(i64 %.t_16)
                    \\    br label %label_loop_continue_2
                    \\label_loop_continue_2:
                    \\    %.t_17 = load i64, ptr %.s_2
                    \\    %.t_18 = add i64 %.t_17, 1
                    \\    store i64 %.t_18, ptr %.s_2
                    \\    br label %label_loop_header_0
                    \\label_loop_exit_3:
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers indexed assignment to a bounds checked store" {
                const source =
                    \\val numbers = [1];
                    \\numbers[0] = 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_panic_index_out_of_bounds(i64, i64, i64, i64) noreturn
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
                    \\    %.t_1 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    %.t_2 = getelementptr inbounds i64, ptr %.t_1, i64 0
                    \\    store i64 1, ptr %.t_2
                    \\    %.t_3 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
                    \\    store i64 1, ptr %.t_3
                    \\    %.t_4 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 1
                    \\    store i64 1, ptr %.t_4
                    \\    %.t_5 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 2
                    \\    store ptr %.t_1, ptr %.t_5
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    %.t_6 = load ptr, ptr %.s_0
                    \\    %.t_7 = getelementptr inbounds %Array, ptr %.t_6, i32 0, i32 0
                    \\    %.t_8 = load i64, ptr %.t_7
                    \\    %.t_9 = getelementptr inbounds %Array, ptr %.t_6, i32 0, i32 2
                    \\    %.t_10 = icmp slt i64 0, 0
                    \\    %.t_11 = icmp sge i64 0, %.t_8
                    \\    %.t_12 = or i1 %.t_10, %.t_11
                    \\    br i1 %.t_12, label %label_index_panic_0, label %label_index_ok_1
                    \\label_index_panic_0:
                    \\    call void @matcha_panic_index_out_of_bounds(i64 2, i64 8, i64 0, i64 %.t_8)
                    \\    unreachable
                    \\label_index_ok_1:
                    \\    %.t_13 = load ptr, ptr %.t_9
                    \\    %.t_14 = getelementptr inbounds i64, ptr %.t_13, i64 0
                    \\    store i64 2, ptr %.t_14
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers append to the runtime slot helper and a typed store" {
                const source =
                    \\val numbers = [1];
                    \\numbers.append(2);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare ptr @matcha_array_append_slot(ptr, i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
                    \\    %.t_1 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    %.t_2 = getelementptr inbounds i64, ptr %.t_1, i64 0
                    \\    store i64 1, ptr %.t_2
                    \\    %.t_3 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
                    \\    store i64 1, ptr %.t_3
                    \\    %.t_4 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 1
                    \\    store i64 1, ptr %.t_4
                    \\    %.t_5 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 2
                    \\    store ptr %.t_1, ptr %.t_5
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    %.t_6 = load ptr, ptr %.s_0
                    \\    %.t_7 = call ptr @matcha_array_append_slot(ptr %.t_6, i64 ptrtoint (ptr getelementptr (i64, ptr null, i64 1) to i64))
                    \\    store i64 2, ptr %.t_7
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const unit_erasure = struct {
            test "erases unit fields and parameters" {
                const source =
                    \\item Mixed = structure { value: int; erased: unit; };
                    \\item consume(nothing: unit, mixed: Mixed): unit = unit;
                    \\consume(unit, Mixed { value = 1, erased = unit });
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\%matcha_structure_0_Mixed = type { i64 }
                    \\
                    \\define void @matcha_function_1_consume(ptr %arg_0_mixed) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    store ptr %arg_0_mixed, ptr %.s_0
                    \\    ret void
                    \\}
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Mixed, ptr null, i32 1) to i64))
                    \\    %.t_1 = getelementptr inbounds %matcha_structure_0_Mixed, ptr %.t_0, i32 0, i32 0
                    \\    store i64 1, ptr %.t_1
                    \\    call void @matcha_function_1_consume(ptr %.t_0)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "allocates a structure with only unit fields as a single byte" {
                const source =
                    \\item Empty = structure { value: unit; };
                    \\item choose(flag: boolean): Empty = if flag {
                    \\    Empty { value = unit }
                    \\} else {
                    \\    Empty { value = unit }
                    \\};
                    \\val chosen = choose(true);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define ptr @matcha_function_1_choose(i1 %arg_0_flag) {
                    \\entry:
                    \\    %.s_0 = alloca i1
                    \\    store i1 %arg_0_flag, ptr %.s_0
                    \\    %.t_0 = load i1, ptr %.s_0
                    \\    br i1 %.t_0, label %label_then_2, label %label_else_1
                    \\label_then_2:
                    \\    %.t_1 = call ptr @matcha_allocate_atomic(i64 1)
                    \\    br label %label_continue_0
                    \\label_else_1:
                    \\    %.t_2 = call ptr @matcha_allocate_atomic(i64 1)
                    \\    br label %label_continue_0
                    \\label_continue_0:
                    \\    %.t_3 = phi ptr [%.t_1, %label_then_2], [%.t_2, %label_else_1]
                    \\    ret ptr %.t_3
                    \\}
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_function_1_choose(i1 1)
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "omits element storage for an array of unit" {
                const source =
                    \\val values: unit[] = [unit, unit];
                    \\printInt(values.length);
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_print_int(i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%Array, ptr null, i32 1) to i64))
                    \\    %.t_2 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 0
                    \\    store i64 2, ptr %.t_2
                    \\    %.t_3 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 1
                    \\    store i64 2, ptr %.t_3
                    \\    %.t_4 = getelementptr inbounds %Array, ptr %.t_0, i32 0, i32 2
                    \\    store ptr null, ptr %.t_4
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    %.t_5 = load ptr, ptr %.s_0
                    \\    %.t_6 = getelementptr inbounds %Array, ptr %.t_5, i32 0, i32 0
                    \\    %.t_7 = load i64, ptr %.t_6
                    \\    call void @matcha_print_int(i64 %.t_7)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const assignment = struct {
            test "lowers a compound assignment to a load operate store sequence" {
                const source =
                    \\var value = 5;
                    \\value += 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca i64
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    store i64 5, ptr %.s_0
                    \\    %.t_0 = load i64, ptr %.s_0
                    \\    %.t_1 = add i64 %.t_0, 2
                    \\    store i64 %.t_1, ptr %.s_0
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers a structure field assignment to a gep and store" {
                const source =
                    \\item Point = structure { x: int; };
                    \\var point = Point { x = 1 };
                    \\point.x = 2;
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\%matcha_structure_0_Point = type { i64 }
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))
                    \\    %.t_1 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0
                    \\    store i64 1, ptr %.t_1
                    \\    store ptr %.t_0, ptr %.s_0
                    \\    %.t_2 = load ptr, ptr %.s_0
                    \\    %.t_3 = getelementptr inbounds %matcha_structure_0_Point, ptr %.t_2, i32 0, i32 0
                    \\    store i64 2, ptr %.t_3
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };

        pub const runtime_calls = struct {
            test "passes a string literal through a function to printString" {
                const source =
                    \\item echo(text: string): string = text;
                    \\printString(echo("hi"));
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_print_string(ptr, i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\@.string_literal_0 = private unnamed_addr constant [2 x i8] c"hi"
                    \\
                    \\define %String @matcha_function_0_echo(%String %arg_0_text) {
                    \\entry:
                    \\    %.s_0 = alloca %String
                    \\    store %String %arg_0_text, ptr %.s_0
                    \\    %.t_0 = load %String, ptr %.s_0
                    \\    ret %String %.t_0
                    \\}
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = getelementptr inbounds [2 x i8], ptr @.string_literal_0, i64 0, i64 0
                    \\    %.t_1 = insertvalue %String undef, ptr %.t_0, 0
                    \\    %.t_2 = insertvalue %String %.t_1, i64 2, 1
                    \\    %.t_3 = call %String @matcha_function_0_echo(%String %.t_2)
                    \\    %.t_4 = extractvalue %String %.t_3, 0
                    \\    %.t_5 = extractvalue %String %.t_3, 1
                    \\    call void @matcha_print_string(ptr %.t_4, i64 %.t_5)
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers the input builtins to runtime calls" {
                const source =
                    \\val line = readLine();
                    \\val input = readFile("input.txt");
                    \\val arguments = getArguments();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_read_file(ptr, ptr, i64)
                    \\declare void @matcha_read_line(ptr)
                    \\declare ptr @matcha_get_arguments()
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\@.string_literal_0 = private unnamed_addr constant [9 x i8] c"input.txt"
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca %String
                    \\    %.s_1 = alloca %String
                    \\    %.s_2 = alloca %String
                    \\    %.s_3 = alloca %String
                    \\    %.s_4 = alloca ptr
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    call void @matcha_read_line(ptr %.s_0)
                    \\    %.t_0 = load %String, ptr %.s_0
                    \\    store %String %.t_0, ptr %.s_1
                    \\    %.t_1 = getelementptr inbounds [9 x i8], ptr @.string_literal_0, i64 0, i64 0
                    \\    %.t_2 = insertvalue %String undef, ptr %.t_1, 0
                    \\    %.t_3 = insertvalue %String %.t_2, i64 9, 1
                    \\    %.t_4 = extractvalue %String %.t_3, 0
                    \\    %.t_5 = extractvalue %String %.t_3, 1
                    \\    call void @matcha_read_file(ptr %.s_2, ptr %.t_4, i64 %.t_5)
                    \\    %.t_6 = load %String, ptr %.s_2
                    \\    store %String %.t_6, ptr %.s_3
                    \\    %.t_7 = call ptr @matcha_get_arguments()
                    \\    store ptr %.t_7, ptr %.s_4
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers the string and integer methods to runtime calls" {
                const source =
                    \\val text = "1";
                    \\val trimmed = text.trim();
                    \\val parts = trimmed.split(",");
                    \\val number = trimmed.toInt();
                    \\val digits = number.toString();
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_string_trim(ptr, ptr, i64)
                    \\declare ptr @matcha_string_split(ptr, i64, ptr, i64)
                    \\declare i64 @matcha_string_to_int(ptr, i64)
                    \\declare void @matcha_int_to_string(ptr, i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\@.string_literal_0 = private unnamed_addr constant [1 x i8] c"1"
                    \\@.string_literal_1 = private unnamed_addr constant [1 x i8] c","
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca %String
                    \\    %.s_1 = alloca %String
                    \\    %.s_2 = alloca %String
                    \\    %.s_3 = alloca ptr
                    \\    %.s_4 = alloca i64
                    \\    %.s_5 = alloca %String
                    \\    %.s_6 = alloca %String
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = getelementptr inbounds [1 x i8], ptr @.string_literal_0, i64 0, i64 0
                    \\    %.t_1 = insertvalue %String undef, ptr %.t_0, 0
                    \\    %.t_2 = insertvalue %String %.t_1, i64 1, 1
                    \\    store %String %.t_2, ptr %.s_0
                    \\    %.t_3 = load %String, ptr %.s_0
                    \\    %.t_4 = extractvalue %String %.t_3, 0
                    \\    %.t_5 = extractvalue %String %.t_3, 1
                    \\    call void @matcha_string_trim(ptr %.s_1, ptr %.t_4, i64 %.t_5)
                    \\    %.t_6 = load %String, ptr %.s_1
                    \\    store %String %.t_6, ptr %.s_2
                    \\    %.t_7 = load %String, ptr %.s_2
                    \\    %.t_8 = getelementptr inbounds [1 x i8], ptr @.string_literal_1, i64 0, i64 0
                    \\    %.t_9 = insertvalue %String undef, ptr %.t_8, 0
                    \\    %.t_10 = insertvalue %String %.t_9, i64 1, 1
                    \\    %.t_11 = extractvalue %String %.t_7, 0
                    \\    %.t_12 = extractvalue %String %.t_7, 1
                    \\    %.t_13 = extractvalue %String %.t_10, 0
                    \\    %.t_14 = extractvalue %String %.t_10, 1
                    \\    %.t_15 = call ptr @matcha_string_split(ptr %.t_11, i64 %.t_12, ptr %.t_13, i64 %.t_14)
                    \\    store ptr %.t_15, ptr %.s_3
                    \\    %.t_16 = load %String, ptr %.s_2
                    \\    %.t_17 = extractvalue %String %.t_16, 0
                    \\    %.t_18 = extractvalue %String %.t_16, 1
                    \\    %.t_19 = call i64 @matcha_string_to_int(ptr %.t_17, i64 %.t_18)
                    \\    store i64 %.t_19, ptr %.s_4
                    \\    %.t_20 = load i64, ptr %.s_4
                    \\    call void @matcha_int_to_string(ptr %.s_5, i64 %.t_20)
                    \\    %.t_21 = load %String, ptr %.s_5
                    \\    store %String %.t_21, ptr %.s_6
                    \\    ret i32 0
                    \\}
                    \\
                );
            }

            test "lowers string operators to runtime calls" {
                const source =
                    \\val joined = "a" + "b";
                    \\val same = joined == "ab";
                    \\val different = joined != "ab";
                ;
                var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                defer arena.deinit();
                const fixture = try setupLlvmIrCodeGeneratorFixture(&arena, source);

                const llvm_ir = fixture.llvm_ir_code_generator.generateLlvmIr(fixture.analyzed_program);

                try expect(llvm_ir).toMatch(
                    \\target triple = "x86_64-unknown-linux-gnu"
                    \\
                    \\declare void @matcha_initiate_garbage_collector()
                    \\declare ptr @matcha_allocate(i64)
                    \\declare ptr @matcha_allocate_atomic(i64)
                    \\declare void @matcha_init_arguments(i32, ptr)
                    \\declare void @matcha_string_concatenate(ptr, ptr, i64, ptr, i64)
                    \\declare i1 @matcha_string_compare(ptr, i64, ptr, i64)
                    \\
                    \\%String = type { ptr, i64 }
                    \\%Array = type { i64, i64, ptr }
                    \\
                    \\@.string_literal_0 = private unnamed_addr constant [1 x i8] c"a"
                    \\@.string_literal_1 = private unnamed_addr constant [1 x i8] c"b"
                    \\@.string_literal_2 = private unnamed_addr constant [2 x i8] c"ab"
                    \\@.string_literal_3 = private unnamed_addr constant [2 x i8] c"ab"
                    \\
                    \\define i32 @main(i32 %argc, ptr %argv) {
                    \\entry:
                    \\    %.s_0 = alloca %String
                    \\    %.s_1 = alloca %String
                    \\    %.s_2 = alloca i1
                    \\    %.s_3 = alloca i1
                    \\    call void @matcha_initiate_garbage_collector()
                    \\    call void @matcha_init_arguments(i32 %argc, ptr %argv)
                    \\    %.t_0 = getelementptr inbounds [1 x i8], ptr @.string_literal_0, i64 0, i64 0
                    \\    %.t_1 = insertvalue %String undef, ptr %.t_0, 0
                    \\    %.t_2 = insertvalue %String %.t_1, i64 1, 1
                    \\    %.t_3 = getelementptr inbounds [1 x i8], ptr @.string_literal_1, i64 0, i64 0
                    \\    %.t_4 = insertvalue %String undef, ptr %.t_3, 0
                    \\    %.t_5 = insertvalue %String %.t_4, i64 1, 1
                    \\    %.t_6 = extractvalue %String %.t_2, 0
                    \\    %.t_7 = extractvalue %String %.t_2, 1
                    \\    %.t_8 = extractvalue %String %.t_5, 0
                    \\    %.t_9 = extractvalue %String %.t_5, 1
                    \\    call void @matcha_string_concatenate(ptr %.s_0, ptr %.t_6, i64 %.t_7, ptr %.t_8, i64 %.t_9)
                    \\    %.t_10 = load %String, ptr %.s_0
                    \\    store %String %.t_10, ptr %.s_1
                    \\    %.t_11 = load %String, ptr %.s_1
                    \\    %.t_12 = getelementptr inbounds [2 x i8], ptr @.string_literal_2, i64 0, i64 0
                    \\    %.t_13 = insertvalue %String undef, ptr %.t_12, 0
                    \\    %.t_14 = insertvalue %String %.t_13, i64 2, 1
                    \\    %.t_15 = extractvalue %String %.t_11, 0
                    \\    %.t_16 = extractvalue %String %.t_11, 1
                    \\    %.t_17 = extractvalue %String %.t_14, 0
                    \\    %.t_18 = extractvalue %String %.t_14, 1
                    \\    %.t_19 = call i1 @matcha_string_compare(ptr %.t_15, i64 %.t_16, ptr %.t_17, i64 %.t_18)
                    \\    store i1 %.t_19, ptr %.s_2
                    \\    %.t_20 = load %String, ptr %.s_1
                    \\    %.t_21 = getelementptr inbounds [2 x i8], ptr @.string_literal_3, i64 0, i64 0
                    \\    %.t_22 = insertvalue %String undef, ptr %.t_21, 0
                    \\    %.t_23 = insertvalue %String %.t_22, i64 2, 1
                    \\    %.t_24 = extractvalue %String %.t_20, 0
                    \\    %.t_25 = extractvalue %String %.t_20, 1
                    \\    %.t_26 = extractvalue %String %.t_23, 0
                    \\    %.t_27 = extractvalue %String %.t_23, 1
                    \\    %.t_28 = call i1 @matcha_string_compare(ptr %.t_24, i64 %.t_25, ptr %.t_26, i64 %.t_27)
                    \\    %.t_29 = xor i1 %.t_28, 1
                    \\    store i1 %.t_29, ptr %.s_3
                    \\    ret i32 0
                    \\}
                    \\
                );
            }
        };
    };
};
