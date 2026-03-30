const std = @import("std");
const emission = @import("emission");
const helpers = @import("../test_helpers.zig");

fn emit(source: []const u8) ![]const u8 {
    var analyzed = try helpers.analyzeProgram(source);
    errdefer analyzed.deinit();

    var llvm_ir_emitter = emission.LlvmIrEmitter.init(analyzed.allocator());
    return llvm_ir_emitter.emitLlvmIr(&analyzed.typed_program);
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

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "xor i1 0, 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "and i1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp sge i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i64") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi void") == null);
}

test "llvm emission skips phi for unit if expressions" {
    const llvm_ir = try emit(
        \\if true { val left = 1; } else { val right = 2; };
        \\val exit_code = 0;
    );

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi ") == null);
}

test "llvm emission produces phi for boolean if expressions" {
    const llvm_ir = try emit(
        \\val flag = if true { true } else { false };
        \\val exit_code = if flag { 1 } else { 0 };
    );

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "phi i1") != null);
}

test "llvm emission uses continue as the false branch for statement ifs" {
    const llvm_ir = try emit(
        \\if true { val x = 1; }
        \\val exit_code = 0;
    );

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "br i1 1, label %label_then_0, label %label_continue_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "label_else_") == null);
}

test "llvm emission compares booleans with icmp eq i1" {
    const llvm_ir = try emit(
        \\val same = true == false;
        \\val exit_code = if same { 1 } else { 0 };
    );

    try std.testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp eq i1") != null);
}
