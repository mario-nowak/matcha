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

pub const CallDispatchDecision = union(enum) {
    UserFunction: struct {
        function_symbol_id: symbols.SymbolId,
        owning_structure_symbol_id: ?symbols.SymbolId = null,
        receiver_node_id: ?NodeId = null,
    },
    Builtin: BuiltinCallKind,
    ArrayMethod: typing.ArrayInstanceMethod,
    StringMethod: typing.StringInstanceMethod,
    IntegerMethod: typing.IntegerInstanceMethod,
};

pub const MemberAccessDecision = union(enum) {
    StructureField: struct {
        field_index: u32,
    },
    ArrayLength,
    StringLength,
    StructureMethod,
    StructureTypeFunction,
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
    And,
    Or,
};

pub const BinaryOperationDecision = union(enum) {
    PrimitiveOperation: PrimitiveBinaryOperation,
    StringConcatenate,
    StringCompareEqual,
    StringCompareNotEqual,
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

pub const NodeValueKind = enum {
    NoValue,
    Value,
};

pub const RuntimeRequirementsPlan = struct {
    print_int: bool = false,
    print_string: bool = false,
    read_file: bool = false,
    read_line: bool = false,
    get_arguments: bool = false,
    string_concatenate: bool = false,
    string_compare: bool = false,
    string_trim: bool = false,
    string_split: bool = false,
    string_to_int: bool = false,
    int_to_string: bool = false,
    panic_index_out_of_bounds: bool = false,
    array_append_slot: bool = false,

    pub fn reset(self: *@This()) void {
        self.* = .{};
    }
};

pub const CallDispatchDecisionByNodeId = std.AutoHashMap(NodeId, CallDispatchDecision);
pub const MemberAccessDecisionByNodeId = std.AutoHashMap(NodeId, MemberAccessDecision);
pub const BinaryOperationDecisionByNodeId = std.AutoHashMap(NodeId, BinaryOperationDecision);
pub const PlaceDecisionByNodeId = std.AutoHashMap(NodeId, PlaceDecision);
pub const NodeValueKindByNodeId = std.AutoHashMap(NodeId, NodeValueKind);
