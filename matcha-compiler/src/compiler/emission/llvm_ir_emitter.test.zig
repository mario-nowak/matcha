const std = @import("std");
const compiler = @import("compiler");
const emission = @import("emission");
const helpers = @import("../test_helpers.zig");

fn emit(source: []const u8) ![]const u8 {
    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    const function_symbol_generator = emission.FunctionSymbolGenerator.init(analyzed.allocator());
    const function_ir_builder = emission.FunctionIrBuilder.init(analyzed.allocator());
    const symbol_generator = emission.SymbolGenerator.init(analyzed.allocator());
    const runtime_call_emitter = emission.RuntimeCallEmitter.init(analyzed.allocator());
    const runtime_symbol_emitter = emission.RuntimeSymbolEmitter.init(analyzed.allocator());
    const string_literal_renderer = emission.StringLiteralRenderer.init(analyzed.allocator());
    const structure_type_definition_renderer = emission.StructureTypeDefinitionRenderer.init(analyzed.allocator());
    var llvm_ir_emitter = emission.LlvmIrEmitter.init(
        analyzed.allocator(),
        compiler.pipeline.getLlvmTargetTriple(),
        function_symbol_generator,
        function_ir_builder,
        symbol_generator,
        runtime_call_emitter,
        runtime_symbol_emitter,
        string_literal_renderer,
        structure_type_definition_renderer,
    );
    const llvm_ir = llvm_ir_emitter.emitLlvmIr(&analyzed.typed_program);
    return try std.testing.allocator.dupe(u8, llvm_ir);
}

fn expectIrContains(llvm_ir: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, needle) != null);
}

fn expectIrNotContains(llvm_ir: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, needle) == null);
}

fn expectIrCountAtLeast(llvm_ir: []const u8, needle: []const u8, minimum_count: usize) !void {
    try std.testing.expect(std.mem.count(u8, llvm_ir, needle) >= minimum_count);
}

fn expectIrCount(llvm_ir: []const u8, needle: []const u8, expected_count: usize) !void {
    try std.testing.expectEqual(expected_count, std.mem.count(u8, llvm_ir, needle));
}

test "llvm emission handles boolean operators comparisons and if expressions" {
    const source =
        \\val flag = not false and true;
        \\if flag { val left = 1; } else { val right = 2; };
        \\val score = if flag { 2 } else { 1 };
        \\val confirmed = score >= 1;
        \\val exit_code = if confirmed { 1 } else { 0 };
    ;

    const llvm_ir = try emit(source);
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "xor i1 0, 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "and i1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp sge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi void") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@printf") == null);
}

test "llvm emission skips phi for unit if expressions" {
    const llvm_ir = try emit(
        \\if true { val left = 1; } else { val right = 2; };
        \\val exit_code = 0;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi ") == null);
}

test "llvm emission produces phi for boolean if expressions" {
    const llvm_ir = try emit(
        \\val flag = if true { true } else { false };
        \\val exit_code = if flag { 1 } else { 0 };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i1") != null);
}

test "llvm emission uses continue as the false branch for statement ifs" {
    const llvm_ir = try emit(
        \\if true { val x = 1; }
        \\val exit_code = 0;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "br i1 1, label %label_then_") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, ", label %label_continue_") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_else_") == null);
}

test "llvm emission compares booleans with icmp eq i1" {
    const llvm_ir = try emit(
        \\val same = true == false;
        \\val exit_code = if same { 1 } else { 0 };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp eq i1") != null);
}

test "llvm emission lowers string-subject match comparisons to runtime string compare" {
    const llvm_ir = try emit(
        \\val tier = "pro";
        \\val score = match tier {
        \\    "basic" => 1,
        \\    "pro" => 2,
        \\    else => 3,
        \\};
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i1 @matcha_string_compare(ptr, i64, ptr, i64)") != null);
    try std.testing.expect(std.mem.count(u8, llvm_ir, "call i1 @matcha_string_compare(") >= 2);
}

test "llvm emission stores and loads mutable variables" {
    const llvm_ir = try emit(
        \\var counter = 1;
        \\counter = counter + 1;
        \\val is_two = counter == 2;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "alloca i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load i64, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 1, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store void") == null);
}

test "llvm emission routes while continue through the update clause" {
    const llvm_ir = try emit(
        \\var i = 0;
        \\while i < 5 : i = i + 1 {
        \\    continue;
        \\}
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_loop_body_1:\n    br label %label_loop_continue_2") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_loop_body_1:\n    br label %label_loop_header_0") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_loop_continue_2:\n    %.t_2 = load i64, ptr %.s_0\n    %.t_3 = add i64 %.t_2, 1\n    store i64 %.t_3, ptr %.s_0\n    br label %label_loop_header_0") != null);
}

test "llvm emission lowers for-in loops over arrays" {
    const llvm_ir = try emit(
        \\val numbers = [1, 2, 3];
        \\for value in numbers {
        \\    printInt(value);
        \\}
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%Array = type { i64, i64, ptr }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %Array, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp slt i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds i64, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_print_int(i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_panic_index_out_of_bounds") == null);
}

test "llvm emission returns from main without implicit printing" {
    const llvm_ir = try emit(
        \\val answer = 41 + 1;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@matcha_print_int") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@matcha_print_string") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i32 @printf") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@.str") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "ret i32 0") != null);
}

test "llvm emission emits user-defined functions and calls them from main" {
    const llvm_ir = try emit(
        \\item identity(value: int): int = value;
        \\val answer = identity(42);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define i64 @matcha_function_0_identity(i64 %arg_0_value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 %arg_0_value, ptr %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call i64 @matcha_function_0_identity(i64 42)") != null);
}

test "llvm emission lowers printInt to a runtime call" {
    const llvm_ir = try emit(
        \\item logValue(value: int): unit = printInt(value);
        \\logValue(7);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_print_int(i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define void @builtin_printInt") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_print_int(i64 %.t_0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_function_0_logValue(i64 7)") != null);
}

test "llvm emission lowers string literals to String globals and runtime printString calls" {
    const llvm_ir = try emit(
        \\item echo(x: string): string = x;
        \\printString("hello");
        \\printString(echo("world"));
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%String = type { i8*, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@.string_literal_0 = private unnamed_addr constant [5 x i8] c\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@.string_literal_1 = private unnamed_addr constant [5 x i8] c\"world\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_print_string(ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define void @builtin_printString") == null);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, llvm_ir, "extractvalue %String "));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, llvm_ir, "call void @matcha_print_string(ptr "));
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define %String @matcha_function_0_echo(%String %arg_0_x)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "alloca %String") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load %String, ptr %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "insertvalue %String undef, i8* %.t_0, 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call %String @matcha_function_0_echo(%String ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@printf") == null);
}

test "llvm emission lowers file input and string helper methods to runtime calls" {
    const llvm_ir = try emit(
        \\val input = readFile("input.txt");
        \\val trimmed = input.trim();
        \\val lines = trimmed.split(",");
        \\val first = lines[0].toInt();
        \\val first_text = first.toString();
        \\printInt(first_text.length + trimmed.length);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_read_file(ptr, ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_string_trim(ptr, ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare ptr @matcha_string_split(ptr, i64, ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i64 @matcha_string_to_int(ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_int_to_string(ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_read_file(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_string_trim(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call ptr @matcha_string_split(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call i64 @matcha_string_to_int(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_int_to_string(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "extractvalue %String") != null);
}

test "llvm emission lowers readLine to a runtime call" {
    const llvm_ir = try emit(
        \\val line = readLine();
        \\printInt(line.length);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_read_line(ptr)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_read_line(ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "alloca %String") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load %String, ptr") != null);
}

test "llvm emission lowers string binary operators to runtime helpers" {
    const llvm_ir = try emit(
        \\var left = "left";
        \\left += "-tail";
        \\val combined = left + "-more";
        \\val is_equal = combined == "left-tail-more";
        \\val is_not_equal = combined != "other";
        \\if is_equal and is_not_equal { printInt(1); } else { printInt(0); };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_string_concatenate(ptr, ptr, i64, ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i1 @matcha_string_compare(ptr, i64, ptr, i64)") != null);
    try std.testing.expect(std.mem.count(u8, llvm_ir, "call void @matcha_string_concatenate(") >= 2);
    try std.testing.expect(std.mem.count(u8, llvm_ir, "call i1 @matcha_string_compare(") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "xor i1") != null);
}

test "llvm emission lowers getArguments to runtime-backed cloned array access" {
    const llvm_ir = try emit(
        \\val args = getArguments();
        \\val count = args.length;
        \\if count > 0 { printString(args[0]); }
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define i32 @main(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_init_arguments(i32, ptr)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare ptr @matcha_get_arguments()") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "@matcha_arguments_cache = internal global ptr null") == null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_init_arguments(i32 %argc, ptr %argv)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call ptr @matcha_get_arguments()") != null);
}

test "llvm emission emits structure definitions as payload types" {
    const llvm_ir = try emit(
        \\item Point = structure { x: int; y: int; };
        \\item User = structure { name: string; friend: User; location: Point; };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_0_Point = type { i64, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_1_User = type { %String, ptr, ptr }") != null);
}

test "llvm emission lowers structure construction" {
    const llvm_ir = try emit(
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { y = 2, x = 1 };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare ptr @matcha_allocate(i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_0_Point = type { i64, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 2, ptr %.t_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 1, ptr %.t_2") != null);
}

test "llvm emission lowers anonymous structure literals with contextual type" {
    const llvm_ir = try emit(
        \\item Point = structure { x: int; y: int; };
        \\val point: Point = .{ y = 2, x = 1 };
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare ptr @matcha_allocate(i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_0_Point = type { i64, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%matcha_structure_0_Point, ptr null, i32 1) to i64))") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 2, ptr %.t_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_0, i32 0, i32 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 1, ptr %.t_2") != null);
}

test "llvm emission lowers structure member access to gep plus load" {
    const llvm_ir = try emit(
        \\item Point = structure { x: int; y: int; };
        \\val point = Point { x = 1, y = 2 };
        \\val x = point.x;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_0_Point = type { i64, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load ptr, ptr %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load i64, ptr %.t_4") != null);
}

test "llvm emission lowers mutable structure field assignment to gep plus store" {
    const llvm_ir = try emit(
        \\item Point = structure { x: int; y: int; };
        \\var point = Point { x = 1, y = 2 };
        \\point.x = 3;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%matcha_structure_0_Point = type { i64, i64 }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load ptr, ptr %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %matcha_structure_0_Point, ptr %.t_3, i32 0, i32 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 3, ptr %.t_4") != null);
}

test "llvm emission lowers indexed assignment to bounds-checked store" {
    const llvm_ir = try emit(
        \\val numbers = [1, 2, 3];
        \\numbers[0] = 4;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%Array = type { i64, i64, ptr }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare void @matcha_panic_index_out_of_bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp slt i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp sge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds i64, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 4, ptr") != null);
}

test "llvm emission lowers compound assignments to load-op-store sequences" {
    const llvm_ir = try emit(
        \\var value = 5;
        \\value += 2;
        \\value -= 1;
        \\value *= 3;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load i64, ptr %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "add i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "sub i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "mul i64") != null);
}

test "llvm emission lowers array length member access to header load" {
    const llvm_ir = try emit(
        \\val numbers = [1, 2, 3];
        \\val length = numbers.length;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "%Array = type { i64, i64, ptr }") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "getelementptr inbounds %Array, ptr") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load i64, ptr") != null);
}

test "llvm emission lowers array append to runtime slot helper plus typed store" {
    const llvm_ir = try emit(
        \\val numbers = [1, 2, 3];
        \\numbers.append(4);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare ptr @matcha_array_append_slot(ptr, i64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call ptr @matcha_array_append_slot(ptr ") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 4, ptr ") != null);
}

test "llvm emission lowers match expressions to compare-and-branch chains" {
    const llvm_ir = try emit(
        \\val first = match true {
        \\    true => 7,
        \\    false => 9,
        \\};
        \\val second = match 2 {
        \\    1 + 1 => "two",
        \\    else => "other",
        \\};
        \\val third = match {
        \\    first == 7 => 1,
        \\    else => 0,
        \\};
        \\val fourth = match "pro" {
        \\    "basic" => 1,
        \\    "pro" => 2,
        \\    else => 3,
        \\};
        \\printInt(fourth);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp eq i1 1, 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp eq i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i1 @matcha_string_compare(ptr, i64, ptr, i64)") != null);
    try std.testing.expect(std.mem.count(u8, llvm_ir, "call i1 @matcha_string_compare(") >= 2);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi %String") != null);
}
