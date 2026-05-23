const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const llvm_type = @import("llvm_type.zig");

pub const LlvmTypeTableLowerer = struct {
    allocator: std.mem.Allocator,
    llvm_ir_type_by_type_id: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .llvm_ir_type_by_type_id = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_ir_type_by_type_id.deinit(self.allocator);
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) []const []const u8 {
        self.llvm_ir_type_by_type_id.clearRetainingCapacity();

        for (0..analyzed_program.type_store.types.items.len) |index| {
            const type_id: typing.TypeId = @intCast(index);
            self.llvm_ir_type_by_type_id.append(
                self.allocator,
                llvm_type.llvmIrType(&analyzed_program.type_store, type_id),
            ) catch unreachable;
        }

        return self.llvm_ir_type_by_type_id.items;
    }
};
