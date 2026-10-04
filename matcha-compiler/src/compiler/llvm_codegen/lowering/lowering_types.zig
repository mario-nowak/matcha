const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");

pub const NodeId = u32;

pub const BuiltinCallKind = enum {
    PrintInt,
    PrintString,
    ReadFile,
    ReadLine,
    GetArguments,
};

pub const UserFunctionCall = struct {
    function_symbol_id: symbols.SymbolId,
    receiver_node_id: ?NodeId = null,
};

pub const CallDispatchDecision = union(enum) {
    UserFunction: UserFunctionCall,
    Builtin: BuiltinCallKind,
    ArrayMethod: typing.ArrayInstanceMethod,
    StringMethod: typing.StringInstanceMethod,
    IntegerMethod: typing.IntegerInstanceMethod,
    UnionConstruction: UnionConstruction,
};

pub const UnionConstruction = struct {
    union_type_id: typing.TypeId,
    case_index: u32,
};

pub const FunctionLayoutParameterIndexKind = union(enum) {
    Absent,
    Index: u32,
};

pub const FunctionLayoutReturnTypeValueKind = enum {
    Absent,
    Present,
};

pub const FunctionLayout = struct {
    llvm_function_name: []const u8,
    parameter_index_kind_by_definition_index: []const FunctionLayoutParameterIndexKind,
    return_type_value_kind: FunctionLayoutReturnTypeValueKind,
};

pub const MemberAccessDecision = union(enum) {
    StructureField: struct {
        field_index: u32,
    },
    UnionConstruction: UnionConstruction,
    ArrayLength,
    StringLength,
    InstanceMethod,
    TypeFunction,
    ArrayMethod,
    StringMethod,
    IntegerMethod,
};

pub const PrimitiveBinaryOperation = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Equal,
    NotEqual,
    LessThan,
    LessThanOrEqual,
    GreaterThan,
    GreaterThanOrEqual,
};

pub const BinaryOperationDecision = union(enum) {
    PrimitiveOperation: PrimitiveBinaryOperation,
    StringConcatenate,
    StringCompareEqual,
    StringCompareNotEqual,
    ZeroSizedCompareEqual,
    ZeroSizedCompareNotEqual,
    UnionCaseIndexComparison,
    ShortCircuitAnd,
    ShortCircuitOr,
};

pub const PlaceDecision = union(enum) {
    IdentifierBinding: struct {
        symbol_id: symbols.SymbolId,
    },
    StructureField: struct {
        field_index: u32,
    },
    ArrayElement,
};

pub const StructureLayoutFieldIndexKind = union(enum) {
    Absent,
    Index: u32,
};

pub const StructureLayout = struct {
    llvm_type_name: []const u8,
    field_index_kind_by_definition_index: []const StructureLayoutFieldIndexKind,
};

pub const StructureLayoutKind = union(enum) {
    Absent,
    Present: StructureLayout,
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
