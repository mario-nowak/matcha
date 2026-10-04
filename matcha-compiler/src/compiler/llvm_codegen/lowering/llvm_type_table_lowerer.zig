const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const llvm_type = @import("llvm_type.zig");

pub const LlvmTypeTableLowerer = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) @This() {
        return .{
            .arena = arena,
        };
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) []const []const u8 {
        var llvm_ir_type_by_type_id = std.ArrayList([]const u8){};

        for (0..analyzed_program.type_store.count()) |index| {
            const type_id: typing.TypeId = @intCast(index);
            llvm_ir_type_by_type_id.append(
                self.arena,
                llvm_type.getLlvmIrTypeByMatchaType(&analyzed_program.type_store, type_id),
            ) catch unreachable;
        }

        return llvm_ir_type_by_type_id.toOwnedSlice(self.arena) catch unreachable;
    }
};
