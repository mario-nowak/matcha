const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const symbols = @import("symbols");
const semantic_analysis = @import("semantic_analysis");
const control_flow_validation = semantic_analysis.control_flow_validation;

const NodeTypeAnalyzer = semantic_analysis.type_checking.NodeTypeAnalyzer;
const ControlFlowValidator = control_flow_validation.ControlFlowValidator;
const StructuralValidator = control_flow_validation.StructuralValidator;
const ExitBehaviorAnalyzer = control_flow_validation.ExitBehaviorAnalyzer;
const setupNameResolverFixture = @import("name_resolver_helpers.zig").setupNameResolverFixture;

const NodeTypeAnalyzerFixture = struct {
    resolved_program: symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    node_type_analyzer: *NodeTypeAnalyzer,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupNodeTypeAnalyzerFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !NodeTypeAnalyzerFixture {
    const name_resolver_fixture = try setupNameResolverFixture(arena, source);
    const resolved_program = try name_resolver_fixture.resolver.resolveProgram(&name_resolver_fixture.program);

    var control_flow_validator = ControlFlowValidator.init(
        StructuralValidator.init(name_resolver_fixture.diagnostic_store),
        ExitBehaviorAnalyzer.init(arena.allocator(), name_resolver_fixture.diagnostic_store),
    );
    const exit_behavior_by_node_id = try control_flow_validator.validateProgram(&name_resolver_fixture.program);

    const node_type_analyzer = try arena.allocator().create(NodeTypeAnalyzer);
    node_type_analyzer.* = NodeTypeAnalyzer.init(arena.allocator(), name_resolver_fixture.diagnostic_store);

    return .{
        .resolved_program = resolved_program,
        .exit_behavior_by_node_id = exit_behavior_by_node_id,
        .node_type_analyzer = node_type_analyzer,
        .diagnostic_store = name_resolver_fixture.diagnostic_store,
    };
}
