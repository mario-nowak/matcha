const std = @import("std");

const semantic_analysis = @import("semantic_analysis");

const lowering_types = @import("lowering_types.zig");

pub const FunctionLayoutLowerer = struct {
    allocator: std.mem.Allocator,
    function_layout_by_symbol_id: lowering_types.FunctionLayoutBySymbolId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .function_layout_by_symbol_id = lowering_types.FunctionLayoutBySymbolId.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.clearLayouts();
        self.function_layout_by_symbol_id.deinit();
    }

    fn clearLayouts(self: *@This()) void {
        var layouts = self.function_layout_by_symbol_id.valueIterator();
        while (layouts.next()) |layout| {
            self.allocator.free(layout.parameter_index_kind_by_definition_index);
        }
        self.function_layout_by_symbol_id.clearRetainingCapacity();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.FunctionLayoutBySymbolId {
        self.clearLayouts();

        var symbols_iterator = analyzed_program.resolved_program.symbol_table.iterator();
        while (symbols_iterator.next()) |symbol| {
            const function_information = switch (symbol.kind) {
                .Function => |function_information| function_information,
                else => continue,
            };
            switch (function_information.implementation_kind) {
                .UserDefined => {},
                else => continue,
            }

            const function_symbol_id = symbol.id;
            var parameter_layout_index: u32 = 0;
            var parameter_index_kind_by_definition_index = std.ArrayList(lowering_types.FunctionLayoutParameterIndexKind){};

            for (function_information.parameter_symbol_ids) |parameter_symbol_id| {
                const parameter_type_id = analyzed_program.type_id_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
                const runtime_representation = analyzed_program
                    .runtime_representation_result
                    .runtime_representation_by_type_id
                    .get(parameter_type_id) orelse unreachable;

                const parameter_index_kind: lowering_types.FunctionLayoutParameterIndexKind = if (runtime_representation.hasRuntimeRepresentation()) block: {
                    const present_parameter_index_kind: lowering_types.FunctionLayoutParameterIndexKind = .{ .Index = parameter_layout_index };
                    parameter_layout_index += 1;
                    break :block present_parameter_index_kind;
                } else .Absent;

                parameter_index_kind_by_definition_index.append(self.allocator, parameter_index_kind) catch unreachable;
            }

            const function_type_id = analyzed_program.type_id_by_symbol_id.get(function_symbol_id) orelse unreachable;
            const return_type_id = switch (analyzed_program.type_store.getType(function_type_id)) {
                .Function => |function_type| function_type.return_type_id,
                else => unreachable,
            };
            const return_runtime_representation = analyzed_program
                .runtime_representation_result
                .runtime_representation_by_type_id
                .get(return_type_id) orelse unreachable;
            const return_type_value_kind: lowering_types.FunctionLayoutReturnTypeValueKind = if (return_runtime_representation.hasRuntimeRepresentation())
                .Present
            else
                .Absent;

            const function_layout = lowering_types.FunctionLayout{
                .parameter_index_kind_by_definition_index = parameter_index_kind_by_definition_index.toOwnedSlice(self.allocator) catch unreachable,
                .return_type_value_kind = return_type_value_kind,
            };

            self.function_layout_by_symbol_id.put(function_symbol_id, function_layout) catch unreachable;
        }

        return self.function_layout_by_symbol_id;
    }
};
