const std = @import("std");

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) == null);
}

test "extracted renderers avoid direct semantic policy switches" {
    const value_renderer = @embedFile("rendering/value_renderer.zig");
    const construction_renderer = @embedFile("rendering/construction_renderer.zig");
    const control_flow_renderer = @embedFile("rendering/control_flow_renderer.zig");

    try expectNotContains(value_renderer, "BuiltinPrintInt");
    try expectNotContains(value_renderer, "BuiltinPrintString");
    try expectNotContains(value_renderer, "BuiltinReadFile");
    try expectNotContains(value_renderer, "BuiltinReadLine");
    try expectNotContains(value_renderer, "BuiltinGetArguments");
    try expectNotContains(value_renderer, "StructureInstanceMethodAccess");
    try expectNotContains(value_renderer, "ArrayInstanceMethodAccess");
    try expectNotContains(value_renderer, "StringInstanceMethodAccess");
    try expectNotContains(value_renderer, "IntegerInstanceMethodAccess");

    try expectNotContains(construction_renderer, "member_access_by_node_id");
    try expectNotContains(construction_renderer, "StructureInstanceFieldAccess");
    try expectNotContains(construction_renderer, "ArrayInstanceFieldAccess");
    try expectNotContains(construction_renderer, "StringInstanceFieldAccess");

    try expectNotContains(control_flow_renderer, "member_access_by_node_id");
    try expectNotContains(control_flow_renderer, "BuiltinPrintInt");
}

test "rendering module exposes runtime helpers from rendering runtime layout" {
    const rendering_module = @embedFile("rendering/module.zig");
    try std.testing.expect(std.mem.indexOf(u8, rendering_module, "pub const runtime = @import(\"runtime/module.zig\")") != null);
}
