const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const typing = @import("typing");
const lowering_types = @import("lowering_types.zig");
const ModuleNameLowerer = @import("module_name_lowerer.zig").ModuleNameLowerer;

pub const UnionLayoutLowerer = struct {
    arena: std.mem.Allocator,
    module_name_lowerer: *const ModuleNameLowerer,

    pub fn init(arena: std.mem.Allocator, module_name_lowerer: *const ModuleNameLowerer) @This() {
        return .{
            .arena = arena,
            .module_name_lowerer = module_name_lowerer,
        };
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) !lowering_types.UnionLayoutByTypeId {
        var union_layout_by_type_id = lowering_types.UnionLayoutByTypeId.init(self.arena);

        var types_iterator = analyzed_program.type_store.iterator();
        while (types_iterator.next()) |entry| {
            const union_type = switch (entry.matcha_type) {
                .@"union" => |union_type| union_type,
                else => continue,
            };

            var union_layout_cases = std.ArrayList(lowering_types.UnionCaseLayout){};
            for (0..union_type.cases.len) |case_index| {
                try union_layout_cases.append(self.arena, lowering_types.UnionCaseLayout{
                    .llvm_type_name = try self.generateLlvmTypeName(analyzed_program, union_type, case_index),
                });
            }

            const union_layout = lowering_types.UnionLayout{
                .cases = try union_layout_cases.toOwnedSlice(self.arena),
            };

            try union_layout_by_type_id.put(
                entry.type_id,
                union_layout,
            );
        }

        return union_layout_by_type_id;
    }

    fn generateLlvmTypeName(
        self: *@This(),
        analyzed_program: *const semantic_analysis.AnalyzedProgram,
        union_type: typing.UnionType,
        case_index: usize,
    ) ![]const u8 {
        const union_symbol = analyzed_program.resolved_program.symbol_table.getSymbol(union_type.symbol_id);
        const union_symbol_information = union_symbol.kind.@"union";
        const union_case = union_symbol_information.cases[case_index];
        const module_name = try self.module_name_lowerer.lower(union_symbol.declared_at.?.module_id);

        return std.fmt.allocPrint(
            self.arena,
            "{s}.union.{s}.case.{s}",
            .{ module_name, union_symbol.name, union_case.name },
        );
    }
};
