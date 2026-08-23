const std = @import("std");
const helpers = @import("../../test_helpers.zig");
const llvm_codegen = @import("llvm_codegen");
const symbols = @import("symbols");

const FunctionLayout = llvm_codegen.lowering.lowering_types.FunctionLayout;
const FunctionLayoutLowerer = llvm_codegen.lowering.FunctionLayoutLowerer;
const FunctionLayoutParameterIndexKind = llvm_codegen.lowering.lowering_types.FunctionLayoutParameterIndexKind;

fn expectParameterIndex(expected: ?u32, actual: FunctionLayoutParameterIndexKind) !void {
    if (expected) |expected_index| {
        switch (actual) {
            .Absent => return error.TestExpectedEqual,
            .Index => |actual_index| try std.testing.expectEqual(expected_index, actual_index),
        }
    } else {
        switch (actual) {
            .Absent => {},
            .Index => return error.TestExpectedEqual,
        }
    }
}

fn expectFunctionLayout(
    layout: FunctionLayout,
    expected_parameter_indices: []const ?u32,
    expected_return_type_value_kind: llvm_codegen.lowering.lowering_types.FunctionLayoutReturnTypeValueKind,
) !void {
    try std.testing.expectEqual(expected_parameter_indices.len, layout.parameter_index_kind_by_definition_index.len);
    for (expected_parameter_indices, layout.parameter_index_kind_by_definition_index) |expected, actual| {
        try expectParameterIndex(expected, actual);
    }
    try std.testing.expectEqual(expected_return_type_value_kind, layout.return_type_value_kind);
}

fn statementSymbolId(analyzed: *const helpers.AnalyzedProgram, statement_index: usize) symbols.SymbolId {
    return analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[statement_index].id).?;
}

test "function layout lowering erases parameters and returns without runtime representation" {
    const source =
        \\item UnitOnly = structure {
        \\    field: unit;
        \\
        \\    item method(self: UnitOnly, erased: unit, value: int): UnitOnly = .{
        \\        field = erased,
        \\    };
        \\};
        \\item select(first: unit, value: int, erased: UnitOnly, suffix: string): UnitOnly = .{
        \\    field = first,
        \\};
        \\item onlyErased(first: unit, second: UnitOnly): int = 42;
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();
    var lowerer = FunctionLayoutLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const layouts = lowerer.lower(&analyzed.typed_program);
    const unit_only_symbol_id = statementSymbolId(&analyzed, 0);
    const resolved_structure = analyzed.typed_program.resolved_program.resolved_structure_by_symbol_id.get(unit_only_symbol_id).?;
    const method_symbol_id = resolved_structure.function_symbol_ids[0];
    const select_symbol_id = statementSymbolId(&analyzed, 1);
    const only_erased_symbol_id = statementSymbolId(&analyzed, 2);

    try expectFunctionLayout(layouts.get(method_symbol_id).?, &.{ null, null, 0 }, .Absent);
    try expectFunctionLayout(layouts.get(select_symbol_id).?, &.{ null, 0, null, 1 }, .Absent);
    try expectFunctionLayout(layouts.get(only_erased_symbol_id).?, &.{ null, null }, .Present);
}
