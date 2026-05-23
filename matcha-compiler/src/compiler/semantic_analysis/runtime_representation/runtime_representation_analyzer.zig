const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const symbols = @import("symbols");
const typing = @import("typing");
const control_flow_validation = @import("../control_flow/module.zig");
const type_checking = @import("../type_checking/module.zig");
const runtime_representation_types = @import("runtime_representation_types.zig");

const RuntimeRepresentation = runtime_representation_types.RuntimeRepresentation;
const RuntimeRepresentationByNodeId = runtime_representation_types.RuntimeRepresentationByNodeId;
const RuntimeRepresentationByTypeId = runtime_representation_types.RuntimeRepresentationByTypeId;

const RuntimeRepresentationAnalysisState = union(enum) {
    Resolving,
    Resolved: RuntimeRepresentation,
};

const RuntimeRepresentationAnalysisStateByTypeId = std.AutoHashMap(typing.TypeId, RuntimeRepresentationAnalysisState);

const AnalysisContext = struct {
    resolved_program: *const symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    type_check_result: *const type_checking.TypeCheckResult,
};

pub const RuntimeRepresentationAnalyzer = struct {
    allocator: std.mem.Allocator,
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,
    runtime_representation_by_type_id: RuntimeRepresentationByTypeId,
    analysis_state_by_type_id: RuntimeRepresentationAnalysisStateByTypeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(allocator),
            .runtime_representation_by_type_id = RuntimeRepresentationByTypeId.init(allocator),
            .analysis_state_by_type_id = RuntimeRepresentationAnalysisStateByTypeId.init(allocator),
        };
    }

    pub fn analyzeProgram(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        type_check_result: *const type_checking.TypeCheckResult,
    ) anyerror!runtime_representation_types.RuntimeRepresentationResult {
        self.runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(self.allocator);
        self.runtime_representation_by_type_id = RuntimeRepresentationByTypeId.init(self.allocator);
        self.analysis_state_by_type_id = RuntimeRepresentationAnalysisStateByTypeId.init(self.allocator);

        try self.seedRuntimeRepresentationByTypeId(&type_check_result.type_store);

        const context = AnalysisContext{
            .resolved_program = resolved_program,
            .exit_behavior_by_node_id = exit_behavior_by_node_id,
            .type_check_result = type_check_result,
        };

        for (resolved_program.program.statements) |*statement| {
            try self.analyzeNode(statement, context);
        }

        return .{
            .runtime_representation_by_node_id = self.runtime_representation_by_node_id,
            .runtime_representation_by_type_id = self.runtime_representation_by_type_id,
        };
    }

    fn seedRuntimeRepresentationByTypeId(
        self: *@This(),
        type_store: *const typing.TypeStore,
    ) anyerror!void {
        for (0..type_store.types.items.len) |index| {
            const type_id: typing.TypeId = @intCast(index);
            _ = try self.resolveRuntimeRepresentationOfType(type_store, type_id);
        }
    }

    fn resolveRuntimeRepresentationOfType(
        self: *@This(),
        type_store: *const typing.TypeStore,
        type_id: typing.TypeId,
    ) anyerror!RuntimeRepresentation {
        if (self.analysis_state_by_type_id.get(type_id)) |analysis_state| {
            return switch (analysis_state) {
                .Resolving => .Present,
                .Resolved => |runtime_representation| runtime_representation,
            };
        }

        try self.analysis_state_by_type_id.put(type_id, .Resolving);

        const runtime_representation = switch (type_store.getType(type_id)) {
            .Unit => .None,
            .Boolean,
            .Integer,
            .String,
            .Function,
            => .Present,
            .Structure => |structure_type_id| try self.resolveRuntimeRepresentationOfStructureType(type_store, structure_type_id),
            .Array => |element_type_id| block: {
                _ = try self.resolveRuntimeRepresentationOfType(type_store, element_type_id);
                break :block RuntimeRepresentation{ .Array = .{ .element_type_id = element_type_id } };
            },
            .TaggedUnion => unreachable,
        };

        try self.analysis_state_by_type_id.put(type_id, .{ .Resolved = runtime_representation });
        try self.runtime_representation_by_type_id.put(type_id, runtime_representation);
        return runtime_representation;
    }

    fn resolveRuntimeRepresentationOfStructureType(
        self: *@This(),
        type_store: *const typing.TypeStore,
        structure_type_id: typing.StructureTypeId,
    ) anyerror!RuntimeRepresentation {
        const structure_type = type_store.structure_types.items[structure_type_id];

        for (structure_type.fields) |field| {
            const field_runtime_representation = try self.resolveRuntimeRepresentationOfType(type_store, field.type_id);
            if (field_runtime_representation.hasRuntimeRepresentation()) {
                return .Present;
            }
        }

        return .None;
    }

    fn analyzeNode(
        self: *@This(),
        node: *const ast.Node,
        context: AnalysisContext,
    ) anyerror!void {
        switch (node.kind) {
            .Declaration => |declaration| try self.analyzeDeclarationNode(node.id, declaration, context),
            .ItemDefinition => |item_definition| try self.analyzeItemDefinitionNode(node.id, item_definition, context),
            .Return => |return_statement| try self.analyzeReturnNode(node.id, return_statement, context),
            .IfStatement => |if_statement| try self.analyzeIfStatementNode(node.id, if_statement, context),
            .ExpressionStatement => |expression_statement| try self.analyzeExpressionStatementNode(node.id, expression_statement, context),
            .Assignment => |assignment| try self.analyzeAssignmentNode(node.id, assignment, context),
            .Loop => |loop| try self.analyzeLoopNode(node.id, loop, context),
            .Leave => |leave_statement| try self.analyzeLeaveNode(node.id, leave_statement, context),
            .Continue => |continue_statement| try self.analyzeContinueNode(node.id, continue_statement, context),
            .While => |while_statement| try self.analyzeWhileNode(node.id, while_statement, context),
            .ForIn => |for_in| try self.analyzeForInNode(node.id, for_in, context),
            .IfExpression => |if_expression| try self.analyzeIfExpressionNode(node.id, if_expression, context),
            .MatchExpression => |match_expression| try self.analyzeMatchExpressionNode(node.id, match_expression, context),
            .CallExpression => |call_expression| try self.analyzeCallExpressionNode(node.id, call_expression, context),
            .MemberAccess => |member_access| try self.analyzeMemberAccessNode(node.id, member_access, context),
            .BinaryExpression => |binary_expression| try self.analyzeBinaryExpressionNode(node.id, binary_expression, context),
            .UnaryExpression => |unary_expression| try self.analyzeUnaryExpressionNode(node.id, unary_expression, context),
            .Identifier => |identifier| try self.analyzeIdentifierNode(node.id, identifier, context),
            .IntegerLiteral => |integer_literal| try self.analyzeIntegerLiteralNode(node.id, integer_literal, context),
            .BooleanLiteral => |boolean_literal| try self.analyzeBooleanLiteralNode(node.id, boolean_literal, context),
            .StringLiteral => |string_literal| try self.analyzeStringLiteralNode(node.id, string_literal, context),
            .UnitLiteral => |unit_literal| try self.analyzeUnitLiteralNode(node.id, unit_literal, context),
            .Block => |block| try self.analyzeBlockNode(node.id, block, context),
            .StructureConstruction => |structure_construction| try self.analyzeStructureConstructionNode(node.id, structure_construction, context),
            .AnonymousStructureLiteral => |anonymous_structure_literal| try self.analyzeAnonymousStructureLiteralNode(node.id, anonymous_structure_literal, context),
            .ArrayLiteral => |array_literal| try self.analyzeArrayLiteralNode(node.id, array_literal, context),
            .IndexAccess => |index_access| try self.analyzeIndexAccessNode(node.id, index_access, context),
        }
    }

    fn recordNodeRuntimeRepresentation(
        self: *@This(),
        node_id: ast.NodeId,
        runtime_representation: RuntimeRepresentation,
    ) void {
        self.runtime_representation_by_node_id.put(node_id, runtime_representation) catch unreachable;
    }

    fn runtimeRepresentationForType(
        self: *const @This(),
        type_id: typing.TypeId,
    ) RuntimeRepresentation {
        return self.runtime_representation_by_type_id.get(type_id) orelse unreachable;
    }

    fn recordNodeRuntimeRepresentationForTypeCheckedNode(
        self: *@This(),
        node_id: ast.NodeId,
        context: AnalysisContext,
    ) void {
        const type_id = context.type_check_result.type_by_node_id.get(node_id) orelse unreachable;
        self.recordNodeRuntimeRepresentation(node_id, self.runtimeRepresentationForType(type_id));
    }

    fn analyzeStructureConstructionFields(
        self: *@This(),
        fields: []const ast.StructureConstructionField,
        context: AnalysisContext,
    ) anyerror!void {
        for (fields) |field| {
            try self.analyzeNode(field.value, context);
        }
    }

    fn analyzeDeclarationNode(self: *@This(), node_id: ast.NodeId, declaration: ast.Declaration, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(declaration.value, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeItemDefinitionNode(self: *@This(), node_id: ast.NodeId, item_definition: ast.ItemDefinition, context: AnalysisContext) anyerror!void {
        switch (item_definition.item) {
            .Function => |function_definition| {
                try self.analyzeNode(function_definition.body_expression, context);
            },
            .Structure => |structure_definition| {
                for (structure_definition.function_definitions) |*function_definition_node| {
                    try self.analyzeNode(function_definition_node, context);
                }
            },
        }

        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeReturnNode(self: *@This(), node_id: ast.NodeId, return_statement: ast.Return, context: AnalysisContext) anyerror!void {
        if (return_statement.value) |value| {
            try self.analyzeNode(value, context);
        }
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeIfStatementNode(self: *@This(), node_id: ast.NodeId, if_statement: ast.IfStatement, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(if_statement.condition, context);
        try self.analyzeNode(if_statement.then_branch, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeExpressionStatementNode(self: *@This(), node_id: ast.NodeId, expression_statement: ast.ExpressionStatement, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(expression_statement.expression, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeAssignmentNode(self: *@This(), node_id: ast.NodeId, assignment: ast.Assignment, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(assignment.target, context);
        try self.analyzeNode(assignment.value, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeLoopNode(self: *@This(), node_id: ast.NodeId, loop: ast.Loop, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(loop.body_block, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeLeaveNode(self: *@This(), node_id: ast.NodeId, leave_statement: ast.Leave, context: AnalysisContext) anyerror!void {
        _ = leave_statement;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeContinueNode(self: *@This(), node_id: ast.NodeId, continue_statement: ast.Continue, context: AnalysisContext) anyerror!void {
        _ = continue_statement;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeWhileNode(self: *@This(), node_id: ast.NodeId, while_statement: ast.While, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(while_statement.condition, context);
        if (while_statement.update) |update| {
            try self.analyzeNode(update, context);
        }
        try self.analyzeNode(while_statement.body_block, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeForInNode(self: *@This(), node_id: ast.NodeId, for_in: ast.ForIn, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(for_in.iterable, context);
        try self.analyzeNode(for_in.body_block, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeIfExpressionNode(self: *@This(), node_id: ast.NodeId, if_expression: ast.IfExpression, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(if_expression.condition, context);
        try self.analyzeNode(if_expression.then_block, context);
        try self.analyzeNode(if_expression.else_block, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeMatchExpressionNode(self: *@This(), node_id: ast.NodeId, match_expression: ast.MatchExpression, context: AnalysisContext) anyerror!void {
        if (match_expression.subject) |subject| {
            try self.analyzeNode(subject, context);
        }

        for (match_expression.arms) |arm| {
            try self.analyzeNode(arm.pattern_or_condition, context);
            try self.analyzeNode(arm.body, context);
        }

        if (match_expression.else_arm) |else_arm| {
            try self.analyzeNode(else_arm, context);
        }

        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeCallExpressionNode(self: *@This(), node_id: ast.NodeId, call_expression: ast.CallExpression, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(call_expression.callee, context);
        for (call_expression.arguments) |*argument| {
            try self.analyzeNode(argument, context);
        }
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeMemberAccessNode(self: *@This(), node_id: ast.NodeId, member_access: ast.MemberAccess, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(member_access.base, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeBinaryExpressionNode(self: *@This(), node_id: ast.NodeId, binary_expression: ast.BinaryExpression, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(binary_expression.left, context);
        try self.analyzeNode(binary_expression.right, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeUnaryExpressionNode(self: *@This(), node_id: ast.NodeId, unary_expression: ast.UnaryExpression, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(unary_expression.operand, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeIdentifierNode(self: *@This(), node_id: ast.NodeId, identifier: lexing.Token, context: AnalysisContext) anyerror!void {
        _ = identifier;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeIntegerLiteralNode(self: *@This(), node_id: ast.NodeId, integer_literal: lexing.Token, context: AnalysisContext) anyerror!void {
        _ = integer_literal;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeBooleanLiteralNode(self: *@This(), node_id: ast.NodeId, boolean_literal: lexing.Token, context: AnalysisContext) anyerror!void {
        _ = boolean_literal;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeStringLiteralNode(self: *@This(), node_id: ast.NodeId, string_literal: lexing.Token, context: AnalysisContext) anyerror!void {
        _ = string_literal;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeUnitLiteralNode(self: *@This(), node_id: ast.NodeId, unit_literal: lexing.Token, context: AnalysisContext) anyerror!void {
        _ = unit_literal;
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeBlockNode(self: *@This(), node_id: ast.NodeId, block: ast.Block, context: AnalysisContext) anyerror!void {
        for (block.statements) |*statement| {
            try self.analyzeNode(statement, context);
        }

        if (block.result) |result| {
            try self.analyzeNode(result, context);
        }

        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeStructureConstructionNode(self: *@This(), node_id: ast.NodeId, structure_construction: ast.StructureConstruction, context: AnalysisContext) anyerror!void {
        try self.analyzeStructureConstructionFields(structure_construction.fields, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeAnonymousStructureLiteralNode(self: *@This(), node_id: ast.NodeId, anonymous_structure_literal: ast.AnonymousStructureLiteral, context: AnalysisContext) anyerror!void {
        try self.analyzeStructureConstructionFields(anonymous_structure_literal.fields, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeArrayLiteralNode(self: *@This(), node_id: ast.NodeId, array_literal: ast.ArrayLiteral, context: AnalysisContext) anyerror!void {
        for (array_literal.elements) |*element| {
            try self.analyzeNode(element, context);
        }

        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }

    fn analyzeIndexAccessNode(self: *@This(), node_id: ast.NodeId, index_access: ast.IndexAccess, context: AnalysisContext) anyerror!void {
        try self.analyzeNode(index_access.base, context);
        try self.analyzeNode(index_access.index, context);
        self.recordNodeRuntimeRepresentationForTypeCheckedNode(node_id, context);
    }
};
