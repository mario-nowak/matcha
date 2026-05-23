const std = @import("std");
const semantic_analysis = @import("semantic_analysis");
const symbols = @import("symbols");
const typing = @import("typing");
const llvm_type = @import("llvm_type.zig");
const lowered_program = @import("lowered_program.zig");
const lowering_types = @import("lowering_types.zig");

pub const LoweringAnalyzer = struct {
    allocator: std.mem.Allocator,
    llvm_ir_type_by_type_id: std.ArrayList([]const u8),
    structure_symbol_id_by_type_id: std.ArrayList(?symbols.SymbolId),
    call_dispatch_decision_by_node_id: lowering_types.CallDispatchDecisionByNodeId,
    member_access_decision_by_node_id: lowering_types.MemberAccessDecisionByNodeId,
    binary_operation_decision_by_node_id: lowering_types.BinaryOperationDecisionByNodeId,
    place_decision_by_node_id: lowering_types.PlaceDecisionByNodeId,
    node_value_kind_by_node_id: lowering_types.NodeValueKindByNodeId,
    runtime_requirements_plan: lowering_types.RuntimeRequirementsPlan,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .llvm_ir_type_by_type_id = .{},
            .structure_symbol_id_by_type_id = .{},
            .call_dispatch_decision_by_node_id = lowering_types.CallDispatchDecisionByNodeId.init(allocator),
            .member_access_decision_by_node_id = lowering_types.MemberAccessDecisionByNodeId.init(allocator),
            .binary_operation_decision_by_node_id = lowering_types.BinaryOperationDecisionByNodeId.init(allocator),
            .place_decision_by_node_id = lowering_types.PlaceDecisionByNodeId.init(allocator),
            .node_value_kind_by_node_id = lowering_types.NodeValueKindByNodeId.init(allocator),
            .runtime_requirements_plan = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_ir_type_by_type_id.deinit(self.allocator);
        self.structure_symbol_id_by_type_id.deinit(self.allocator);
        self.call_dispatch_decision_by_node_id.deinit();
        self.member_access_decision_by_node_id.deinit();
        self.binary_operation_decision_by_node_id.deinit();
        self.place_decision_by_node_id.deinit();
        self.node_value_kind_by_node_id.deinit();
    }

    pub fn analyzeProgram(self: *@This(), analyzed_program: *const semantic_analysis.AnalyzedProgram) lowered_program.LoweredProgram {
        self.llvm_ir_type_by_type_id.clearRetainingCapacity();
        self.structure_symbol_id_by_type_id.clearRetainingCapacity();
        self.call_dispatch_decision_by_node_id.clearRetainingCapacity();
        self.member_access_decision_by_node_id.clearRetainingCapacity();
        self.binary_operation_decision_by_node_id.clearRetainingCapacity();
        self.place_decision_by_node_id.clearRetainingCapacity();
        self.node_value_kind_by_node_id.clearRetainingCapacity();
        self.runtime_requirements_plan.reset();

        for (0..analyzed_program.type_store.types.items.len) |index| {
            const type_id: typing.TypeId = @intCast(index);
            self.llvm_ir_type_by_type_id.append(
                self.allocator,
                llvm_type.llvmIrType(&analyzed_program.type_store, type_id),
            ) catch unreachable;
            self.structure_symbol_id_by_type_id.append(self.allocator, null) catch unreachable;
        }

        var type_by_symbol_iterator = analyzed_program.type_by_symbol_id.iterator();
        while (type_by_symbol_iterator.next()) |entry| {
            const symbol_id = entry.key_ptr.*;
            const type_id = entry.value_ptr.*;
            const symbol = analyzed_program.resolved_program.symbol_table.getSymbol(symbol_id);
            switch (symbol.kind) {
                .Structure => self.structure_symbol_id_by_type_id.items[@intCast(type_id)] = symbol_id,
                else => {},
            }
        }

        var member_access_iterator = analyzed_program.member_access_by_node_id.iterator();
        while (member_access_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const member_access = entry.value_ptr.*;
            const decision: lowering_types.MemberAccessDecision = switch (member_access) {
                .StructureInstanceFieldAccess => |structure_field| .{
                    .StructureField = .{ .field_index = structure_field.field_index },
                },
                .StructureInstanceMethodAccess => .StructureMethod,
                .StructureTypeFunctionAccess => .StructureTypeFunction,
                .ArrayInstanceMethodAccess => .ArrayMethod,
                .ArrayInstanceFieldAccess => .ArrayLength,
                .StringInstanceMethodAccess => .StringMethod,
                .StringInstanceFieldAccess => .StringLength,
                .IntegerInstanceMethodAccess => .IntegerMethod,
            };
            self.member_access_decision_by_node_id.put(node_id, decision) catch unreachable;
        }

        var type_by_node_iterator = analyzed_program.type_by_node_id.iterator();
        while (type_by_node_iterator.next()) |entry| {
            const node_id = entry.key_ptr.*;
            const type_id = entry.value_ptr.*;
            const value_kind: lowering_types.NodeValueKind = if (type_id == analyzed_program.type_store.unit_type_id)
                .NoValue
            else
                .Value;
            self.node_value_kind_by_node_id.put(node_id, value_kind) catch unreachable;
        }

        return .{
            .analyzed_program = analyzed_program,
            .llvm_ir_type_by_type_id = self.llvm_ir_type_by_type_id.items,
            .structure_symbol_id_by_type_id = self.structure_symbol_id_by_type_id.items,
            .call_dispatch_decision_by_node_id = self.call_dispatch_decision_by_node_id,
            .member_access_decision_by_node_id = self.member_access_decision_by_node_id,
            .binary_operation_decision_by_node_id = self.binary_operation_decision_by_node_id,
            .place_decision_by_node_id = self.place_decision_by_node_id,
            .node_value_kind_by_node_id = self.node_value_kind_by_node_id,
            .runtime_requirements_plan = self.runtime_requirements_plan,
        };
    }
};
