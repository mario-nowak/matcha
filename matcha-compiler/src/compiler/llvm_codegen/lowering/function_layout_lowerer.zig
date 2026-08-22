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
            self.allocator.free(layout.parameter_index_by_definition_index);
        }
        self.function_layout_by_symbol_id.clearRetainingCapacity();
    }

    pub fn lower(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowering_types.FunctionLayoutBySymbolId {
        self.clearLayouts();

        var resolved_functions = analyzed_program.resolved_program.resolved_function_by_symbol_id.iterator();
        while (resolved_functions.next()) |entry| {
            const resolved_function = entry.value_ptr;
            switch (resolved_function.implementation) {
                .builtin => continue,
                .user_defined => {},
            }

            const function_symbol_id = entry.key_ptr.*;
            var parameter_layout_index: u32 = 0;
            var parameter_index_by_definition_index = std.ArrayList(lowering_types.FunctionParameterIndex){};

            for (resolved_function.parameters) |parameter| {
                const parameter_type_id = analyzed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
                const runtime_representation = analyzed_program
                    .runtime_representation_result
                    .runtime_representation_by_type_id
                    .get(parameter_type_id) orelse unreachable;

                const parameter_index: lowering_types.FunctionParameterIndex = if (runtime_representation.hasRuntimeRepresentation()) block: {
                    const parameter_layout: lowering_types.FunctionParameterIndex = .{ .Index = parameter_layout_index };
                    parameter_layout_index += 1;
                    break :block parameter_layout;
                } else .Absent;

                parameter_index_by_definition_index.append(self.allocator, parameter_index) catch unreachable;
            }

            const function_type_id = analyzed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
            const return_type_id = switch (analyzed_program.type_store.getType(function_type_id)) {
                .Function => |function_type_index| analyzed_program.type_store.function_types.items[function_type_index].return_type,
                else => unreachable,
            };
            const return_runtime_representation = analyzed_program
                .runtime_representation_result
                .runtime_representation_by_type_id
                .get(return_type_id) orelse unreachable;
            const runtime_return_kind: lowering_types.RuntimeReturnKind = if (return_runtime_representation.hasRuntimeRepresentation())
                .Present
            else
                .Absent;

            const function_layout = lowering_types.FunctionLayout{
                .parameter_index_by_definition_index = parameter_index_by_definition_index.toOwnedSlice(self.allocator) catch unreachable,
                .runtime_return_kind = runtime_return_kind,
            };

            self.function_layout_by_symbol_id.put(function_symbol_id, function_layout) catch unreachable;
        }

        return self.function_layout_by_symbol_id;
    }
};
