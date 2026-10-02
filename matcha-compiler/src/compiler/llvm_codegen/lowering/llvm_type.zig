const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");
const semantic_analysis = @import("semantic_analysis");

// The runtime library defines the layouts of strings and arrays, so these structure types must match it.
// A string is a header containing a pointer to the data and the length.
pub const string_llvm_type_name = "String";
pub const string_llvm_type = "%" ++ string_llvm_type_name;
pub const string_llvm_type_definition = string_llvm_type ++ " = type { ptr, i64 }";
// An array is a header containing the length, capacity, and a pointer to the data.
pub const array_llvm_type_name = "Array";
pub const array_llvm_type = "%" ++ array_llvm_type_name;
pub const array_llvm_type_definition = array_llvm_type ++ " = type { i64, i64, ptr }";
pub const array_length_field_index: u32 = 0;
pub const array_capacity_field_index: u32 = 1;
pub const array_data_field_index: u32 = 2;

pub fn getLlvmIrTypeByMatchaType(type_store: *const typing.TypeStore, type_id: typing.TypeId) []const u8 {
    return switch (type_store.getType(type_id)) {
        .Unit => "void",
        .Boolean => "i1",
        .Integer => "i64",
        .String => string_llvm_type,
        .Structure => "ptr",
        .Array => "ptr",
        .Function => "ptr",
        .Union => "ptr",
        // Internal type
        .UnionConstructor => "ptr",
    };
}

pub fn getTypeIdFromResolvedTypeReference(
    typed_program: *const semantic_analysis.AnalyzedProgram,
    type_reference: symbols.ResolvedTypeReference,
) typing.TypeId {
    return switch (type_reference) {
        .Builtin => |builtin_type| switch (builtin_type) {
            .Unit => typed_program.type_store.unit_type_id,
            .Boolean => typed_program.type_store.boolean_type_id,
            .Integer => typed_program.type_store.integer_type_id,
            .String => typed_program.type_store.string_type_id,
        },
        .Symbol => |symbol_id| typed_program.type_id_by_symbol_id.get(symbol_id).?,
        .Array => |element_type_reference| typed_program.type_store.getArrayType(
            getTypeIdFromResolvedTypeReference(typed_program, element_type_reference.*),
        ).?,
    };
}

pub fn getLlvmIrTypeFromResolvedTypeReference(
    typed_program: *const semantic_analysis.AnalyzedProgram,
    type_reference: symbols.ResolvedTypeReference,
) []const u8 {
    return getLlvmIrTypeByMatchaType(
        &typed_program.type_store,
        getTypeIdFromResolvedTypeReference(typed_program, type_reference),
    );
}
