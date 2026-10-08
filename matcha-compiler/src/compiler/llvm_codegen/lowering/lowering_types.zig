const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");

pub const NodeId = u32;

pub const BuiltinCallKind = enum {
    print_int,
    print_string,
    read_file,
    read_line,
    get_arguments,
    start_process,
};

pub const UserFunctionCall = struct {
    function_symbol_id: symbols.SymbolId,
    receiver_node_id: ?NodeId = null,
};

pub const CallDispatchDecision = union(enum) {
    user_function: UserFunctionCall,
    builtin: BuiltinCallKind,
    array_method: typing.ArrayInstanceMethod,
    string_method: typing.StringInstanceMethod,
    integer_method: typing.IntegerInstanceMethod,
    union_construction: UnionConstruction,
};

pub const UnionConstruction = struct {
    union_type_id: typing.TypeId,
    case_index: u32,
};

pub const FunctionLayoutParameterIndexKind = union(enum) {
    absent,
    index: u32,
};

pub const FunctionLayoutReturnTypeValueKind = enum {
    absent,
    present,
};

pub const FunctionLayout = struct {
    llvm_function_name: []const u8,
    parameter_index_kind_by_definition_index: []const FunctionLayoutParameterIndexKind,
    return_type_value_kind: FunctionLayoutReturnTypeValueKind,
};

pub const MemberAccessDecision = union(enum) {
    structure_field: struct {
        field_index: u32,
    },
    union_construction: UnionConstruction,
    array_length,
    string_length,
    instance_method,
    type_function,
    array_method,
    string_method,
    integer_method,
};

pub const PrimitiveBinaryOperation = enum {
    add,
    subtract,
    multiply,
    equal,
    not_equal,
    less_than,
    less_than_or_equal,
    greater_than,
    greater_than_or_equal,
};

pub const BinaryOperationDecision = union(enum) {
    primitive_operation: PrimitiveBinaryOperation,
    string_concatenate,
    string_compare_equal,
    string_compare_not_equal,
    zero_sized_compare_equal,
    zero_sized_compare_not_equal,
    union_case_index_comparison,
    short_circuit_and,
    short_circuit_or,
    checked_divide,
};

pub const PlaceDecision = union(enum) {
    identifier_binding: struct {
        symbol_id: symbols.SymbolId,
    },
    structure_field: struct {
        field_index: u32,
    },
    array_element,
};

pub const StructureLayoutFieldIndexKind = union(enum) {
    absent,
    index: u32,
};

pub const StructureLayout = struct {
    llvm_type_name: []const u8,
    field_index_kind_by_definition_index: []const StructureLayoutFieldIndexKind,
};

pub const StructureLayoutKind = union(enum) {
    absent,
    present: StructureLayout,
};

// Every union case is a structure that holds the case index first and the payload, if it has one, second.
pub const union_case_index_llvm_type = "i32";
pub const union_case_index_field_index: u32 = 0;
pub const union_payload_field_index: u32 = 1;

pub const UnionLayout = struct {
    cases: []const UnionCaseLayout,
};

pub const UnionCaseLayout = struct {
    llvm_type_name: []const u8,
};

pub const CallDispatchDecisionByNodeId = std.AutoHashMap(NodeId, CallDispatchDecision);
pub const MemberAccessDecisionByNodeId = std.AutoHashMap(NodeId, MemberAccessDecision);
pub const BinaryOperationDecisionByNodeId = std.AutoHashMap(NodeId, BinaryOperationDecision);
pub const PlaceDecisionByNodeId = std.AutoHashMap(NodeId, PlaceDecision);
pub const StructureLayoutKindByTypeId = std.AutoHashMap(typing.TypeId, StructureLayoutKind);
pub const UnionLayoutByTypeId = std.AutoHashMap(typing.TypeId, UnionLayout);
pub const FunctionLayoutBySymbolId = std.AutoHashMap(symbols.SymbolId, FunctionLayout);
