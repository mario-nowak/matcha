const std = @import("std");

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) == null);
}

test "node renderer avoids direct semantic policy switches for lowered decisions" {
    const node_renderer = @embedFile("rendering/node_renderer.zig");

    try expectNotContains(node_renderer, "BuiltinPrintInt");
    try expectNotContains(node_renderer, "BuiltinPrintString");
    try expectNotContains(node_renderer, "BuiltinReadFile");
    try expectNotContains(node_renderer, "BuiltinReadLine");
    try expectNotContains(node_renderer, "BuiltinGetArguments");
    try expectNotContains(node_renderer, "StructureInstanceFieldAccess");
    try expectNotContains(node_renderer, "ArrayInstanceFieldAccess");
    try expectNotContains(node_renderer, "StringInstanceFieldAccess");
    try expectNotContains(node_renderer, "StructureInstanceMethodAccess");
    try expectNotContains(node_renderer, "ArrayInstanceMethodAccess");
    try expectNotContains(node_renderer, "StringInstanceMethodAccess");
    try expectNotContains(node_renderer, "IntegerInstanceMethodAccess");
    try expectNotContains(node_renderer, "member_access_by_node_id");
}

test "lowering analyzer uses injected collaborators" {
    const lowering_analyzer = @embedFile("lowering/lowering_analyzer.zig");

    try expectNotContains(lowering_analyzer, "pub fn init(allocator: std.mem.Allocator)");
    try std.testing.expect(std.mem.indexOf(u8, lowering_analyzer, "llvm_type_table_lowerer: LlvmTypeTableLowerer") != null);
    try std.testing.expect(std.mem.indexOf(u8, lowering_analyzer, "runtime_requirements_lowerer: RuntimeRequirementsLowerer") != null);
}

test "rendering module exposes runtime helpers from rendering runtime layout" {
    const rendering_module = @embedFile("rendering/module.zig");
    try std.testing.expect(std.mem.indexOf(u8, rendering_module, "pub const runtime = @import(\"runtime/module.zig\")") != null);
}
