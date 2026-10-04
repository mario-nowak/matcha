const typing = @import("typing");
const runtime_symbols = @import("runtime_symbols");

// The runtime library defines the layouts of strings and arrays, so these structure types must match it.
// A string is a header containing a pointer to the data and the length.
pub const string_llvm_type_name = runtime_symbols.builtinType("string");
pub const string_llvm_type = "%" ++ string_llvm_type_name;
pub const string_llvm_type_definition = string_llvm_type ++ " = type { ptr, i64 }";
// An array is a header containing the length, capacity, and a pointer to the data.
pub const array_llvm_type_name = runtime_symbols.builtinType("array");
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
