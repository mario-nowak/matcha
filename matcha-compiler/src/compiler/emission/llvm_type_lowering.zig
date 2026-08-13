const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");
const semantic_analysis = @import("semantic_analysis");

pub fn llvmIrType(type_store: *const typing.TypeStore, type_id: typing.TypeId) []const u8 {
    return switch (type_store.getType(type_id)) {
        .Unit => "void",
        .Boolean => "i1",
        .Integer => "i64",
        .String => "%String",
        .Structure => "ptr",
        .Array => "ptr",
        .Function => |unsupported_type| std.debug.panic(
            "LLVM IR emitter does not support function values, got {any} (type id {d})",
            .{ unsupported_type, type_id },
        ),
        .TaggedUnion => |unsupported_type| std.debug.panic(
            "LLVM IR emitter only supports builtin types for now, got {any} (type id {d})",
            .{ unsupported_type, type_id },
        ),
    };
}

pub fn typeIdFromResolvedTypeReference(
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
        .Symbol => |symbol_id| typed_program.type_by_symbol_id.get(symbol_id) orelse unreachable,
        .Array => |element_type_reference| typed_program.type_store.getArrayType(
            typeIdFromResolvedTypeReference(typed_program, element_type_reference.*),
        ) orelse unreachable,
    };
}

pub fn llvmIrTypeFromResolvedTypeReference(
    typed_program: *const semantic_analysis.AnalyzedProgram,
    type_reference: symbols.ResolvedTypeReference,
) []const u8 {
    return llvmIrType(
        &typed_program.type_store,
        typeIdFromResolvedTypeReference(typed_program, type_reference),
    );
}
