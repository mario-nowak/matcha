const std = @import("std");
const emission = @import("emission");
const helpers = @import("../test_helpers.zig");

fn emit(source: []const u8) ![]const u8 {
    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();

    var llvm_ir_emitter = emission.LlvmIrEmitter.init(analyzed.allocator());
    const llvm_ir = llvm_ir_emitter.emitLlvmIr(&analyzed.typed_program);
    return try std.testing.allocator.dupe(u8, llvm_ir);
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

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "br i1 1, label %label_then_0, label %label_continue_1") != null);
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

test "llvm emission stores and loads mutable variables" {
    const llvm_ir = try emit(
        \\var counter = 1;
        \\counter = counter + 1;
        \\val is_two = counter == 2;
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "alloca i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "load i64, i64*") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 1, i64*") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_loop_continue_2:\n    %.t_2 = load i64, i64* %.s_0\n    %.t_3 = add i64 %.t_2, 1\n    store i64 %.t_3, i64* %.s_0\n    br label %label_loop_header_0") != null);
}

test "llvm emission returns from main without implicit printing" {
    const llvm_ir = try emit(
        \\val answer = 41 + 1;
    );
    defer std.testing.allocator.free(llvm_ir);

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

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define i64 @matcha_0_identity(i64 %arg_0_value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "store i64 %arg_0_value, i64* %.s_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call i64 @matcha_0_identity(i64 42)") != null);
}

test "llvm emission lowers printInt as a real llvm function" {
    const llvm_ir = try emit(
        \\item logValue(value: int): unit = printInt(value);
        \\logValue(7);
    );
    defer std.testing.allocator.free(llvm_ir);

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "declare i32 @printf") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "define void @builtin_printInt(i64 %arg_0_value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @builtin_printInt(i64 %.t_0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "call void @matcha_0_logValue(i64 7)") != null);
}
