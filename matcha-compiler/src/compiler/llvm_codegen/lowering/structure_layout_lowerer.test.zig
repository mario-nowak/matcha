const std = @import("std");
const helpers = @import("../../test_helpers.zig");
const llvm_codegen = @import("llvm_codegen");

const RuntimeFieldIndex = llvm_codegen.lowering.lowering_types.RuntimeFieldIndex;
const StructureLayoutLowerer = llvm_codegen.lowering.StructureLayoutLowerer;

fn expectFieldIndex(expected: ?u32, actual: RuntimeFieldIndex) !void {
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

test "structure layout lowering erases fields without runtime representation" {
    const source =
        \\item UnitOnly = structure {
        \\    first: unit;
        \\    second: unit;
        \\};
        \\item Mixed = structure {
        \\    first: int;
        \\    erased: unit;
        \\    nested: UnitOnly;
        \\    last: string;
        \\};
    ;

    var analyzed = try helpers.analyzeProgram(source);
    defer analyzed.deinit();
    var lowerer = StructureLayoutLowerer.init(std.testing.allocator);
    defer lowerer.deinit();

    const layouts = lowerer.lower(&analyzed.typed_program);
    const unit_only_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[0].id).?;
    const unit_only_type_id = analyzed.typed_program.type_by_symbol_id.get(unit_only_symbol_id).?;
    const mixed_symbol_id = analyzed.typed_program.resolved_program.symbol_id_by_node_id.get(analyzed.parsed.program.statements[1].id).?;
    const mixed_type_id = analyzed.typed_program.type_by_symbol_id.get(mixed_symbol_id).?;

    switch (layouts.get(unit_only_type_id).?) {
        .Absent => {},
        .Present => return error.TestExpectedEqual,
    }

    const mixed_layout = switch (layouts.get(mixed_type_id).?) {
        .Absent => return error.TestExpectedEqual,
        .Present => |layout| layout,
    };
    try std.testing.expectEqual(@as(usize, 4), mixed_layout.field_index_by_definition_index.len);
    try expectFieldIndex(0, mixed_layout.field_index_by_definition_index[0]);
    try expectFieldIndex(null, mixed_layout.field_index_by_definition_index[1]);
    try expectFieldIndex(null, mixed_layout.field_index_by_definition_index[2]);
    try expectFieldIndex(1, mixed_layout.field_index_by_definition_index[3]);
}
