const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const symbols = @import("symbols");
const control_flow_validation = @import("../control_flow/module.zig");
const type_checking = @import("../type_checking/module.zig");
const runtime_representation_types = @import("runtime_representation_types.zig");

const RuntimeRepresentation = runtime_representation_types.RuntimeRepresentation;
const RuntimeRepresentationByNodeId = runtime_representation_types.RuntimeRepresentationByNodeId;

const AnalysisContext = struct {
    resolved_program: *const symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    type_check_result: *const type_checking.TypeCheckResult,
};

pub const RuntimeRepresentationAnalyzer = struct {
    allocator: std.mem.Allocator,
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(allocator),
        };
    }

    pub fn analyzeProgram(
        self: *@This(),
        resolved_program: *const symbols.ResolvedProgram,
        exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
        type_check_result: *const type_checking.TypeCheckResult,
    ) anyerror!runtime_representation_types.RuntimeRepresentationResult {
        self.runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(self.allocator);

        const context = AnalysisContext{
            .resolved_program = resolved_program,
            .exit_behavior_by_node_id = exit_behavior_by_node_id,
            .type_check_result = type_check_result,
        };

        for (resolved_program.program.statements) |*statement| {
            _ = try self.analyzeNode(statement, context);
        }

        return .{
            .runtime_representation_by_node_id = self.runtime_representation_by_node_id,
        };
    }

    fn analyzeNode(
        self: *@This(),
        node: *const ast.Node,
        context: AnalysisContext,
    ) anyerror!RuntimeRepresentation {
        return switch (node.kind) {
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
        };
    }

    fn recordNodeRuntimeRepresentation(
        self: *@This(),
        node_id: ast.NodeId,
        runtime_representation: RuntimeRepresentation,
    ) RuntimeRepresentation {
        self.runtime_representation_by_node_id.put(node_id, runtime_representation) catch unreachable;
        return runtime_representation;
    }

    fn analyzeDeclarationNode(self: *@This(), node_id: ast.NodeId, declaration: ast.Declaration, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = try self.analyzeNode(declaration.value, context);
        return self.recordNodeRuntimeRepresentation(node_id, .None);
    }

    fn analyzeItemDefinitionNode(self: *@This(), node_id: ast.NodeId, item_definition: ast.ItemDefinition, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = item_definition;
        _ = context;
        unreachable;
    }

    fn analyzeReturnNode(self: *@This(), node_id: ast.NodeId, return_statement: ast.Return, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = return_statement;
        _ = context;
        unreachable;
    }

    fn analyzeIfStatementNode(self: *@This(), node_id: ast.NodeId, if_statement: ast.IfStatement, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = if_statement;
        _ = context;
        unreachable;
    }

    fn analyzeExpressionStatementNode(self: *@This(), node_id: ast.NodeId, expression_statement: ast.ExpressionStatement, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = expression_statement;
        _ = context;
        unreachable;
    }

    fn analyzeAssignmentNode(self: *@This(), node_id: ast.NodeId, assignment: ast.Assignment, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = assignment;
        _ = context;
        unreachable;
    }

    fn analyzeLoopNode(self: *@This(), node_id: ast.NodeId, loop: ast.Loop, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = loop;
        _ = context;
        unreachable;
    }

    fn analyzeLeaveNode(self: *@This(), node_id: ast.NodeId, leave_statement: ast.Leave, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = leave_statement;
        _ = context;
        unreachable;
    }

    fn analyzeContinueNode(self: *@This(), node_id: ast.NodeId, continue_statement: ast.Continue, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = continue_statement;
        _ = context;
        unreachable;
    }

    fn analyzeWhileNode(self: *@This(), node_id: ast.NodeId, while_statement: ast.While, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = while_statement;
        _ = context;
        unreachable;
    }

    fn analyzeForInNode(self: *@This(), node_id: ast.NodeId, for_in: ast.ForIn, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = for_in;
        _ = context;
        unreachable;
    }

    fn analyzeIfExpressionNode(self: *@This(), node_id: ast.NodeId, if_expression: ast.IfExpression, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = if_expression;
        _ = context;
        unreachable;
    }

    fn analyzeMatchExpressionNode(self: *@This(), node_id: ast.NodeId, match_expression: ast.MatchExpression, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = match_expression;
        _ = context;
        unreachable;
    }

    fn analyzeCallExpressionNode(self: *@This(), node_id: ast.NodeId, call_expression: ast.CallExpression, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = call_expression;
        _ = context;
        unreachable;
    }

    fn analyzeMemberAccessNode(self: *@This(), node_id: ast.NodeId, member_access: ast.MemberAccess, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = member_access;
        _ = context;
        unreachable;
    }

    fn analyzeBinaryExpressionNode(self: *@This(), node_id: ast.NodeId, binary_expression: ast.BinaryExpression, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = binary_expression;
        _ = context;
        unreachable;
    }

    fn analyzeUnaryExpressionNode(self: *@This(), node_id: ast.NodeId, unary_expression: ast.UnaryExpression, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = unary_expression;
        _ = context;
        unreachable;
    }

    fn analyzeIdentifierNode(self: *@This(), node_id: ast.NodeId, identifier: lexing.Token, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = identifier;
        _ = context;
        unreachable;
    }

    fn analyzeIntegerLiteralNode(self: *@This(), node_id: ast.NodeId, integer_literal: lexing.Token, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = integer_literal;
        _ = context;
        unreachable;
    }

    fn analyzeBooleanLiteralNode(self: *@This(), node_id: ast.NodeId, boolean_literal: lexing.Token, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = boolean_literal;
        _ = context;
        unreachable;
    }

    fn analyzeStringLiteralNode(self: *@This(), node_id: ast.NodeId, string_literal: lexing.Token, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = string_literal;
        _ = context;
        unreachable;
    }

    fn analyzeUnitLiteralNode(self: *@This(), node_id: ast.NodeId, unit_literal: lexing.Token, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = unit_literal;
        _ = context;
        return self.recordNodeRuntimeRepresentation(node_id, .None);
    }

    fn analyzeBlockNode(self: *@This(), node_id: ast.NodeId, block: ast.Block, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = block;
        _ = context;
        unreachable;
    }

    fn analyzeStructureConstructionNode(self: *@This(), node_id: ast.NodeId, structure_construction: ast.StructureConstruction, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = structure_construction;
        _ = context;
        unreachable;
    }

    fn analyzeAnonymousStructureLiteralNode(self: *@This(), node_id: ast.NodeId, anonymous_structure_literal: ast.AnonymousStructureLiteral, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = anonymous_structure_literal;
        _ = context;
        unreachable;
    }

    fn analyzeArrayLiteralNode(self: *@This(), node_id: ast.NodeId, array_literal: ast.ArrayLiteral, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = array_literal;
        _ = context;
        unreachable;
    }

    fn analyzeIndexAccessNode(self: *@This(), node_id: ast.NodeId, index_access: ast.IndexAccess, context: AnalysisContext) anyerror!RuntimeRepresentation {
        _ = self;
        _ = node_id;
        _ = index_access;
        _ = context;
        unreachable;
    }
};
