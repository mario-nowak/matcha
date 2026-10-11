const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const sources = @import("sources");
const symbols = @import("symbols");
const semantic_analysis = @import("semantic_analysis");
const control_flow_validation = semantic_analysis.control_flow_validation;

const NodeTypeAnalyzer = semantic_analysis.type_checking.NodeTypeAnalyzer;
const ControlFlowValidator = control_flow_validation.ControlFlowValidator;
const StructuralValidator = control_flow_validation.StructuralValidator;
const ExitBehaviorAnalyzer = control_flow_validation.ExitBehaviorAnalyzer;
const setupNameResolverFixtureFromSourceFiles = @import("name_resolver_helpers.zig").setupNameResolverFixtureFromSourceFiles;

const NodeTypeAnalyzerFixture = struct {
    resolved_program: symbols.ResolvedProgram,
    exit_behavior_by_node_id: control_flow_validation.ExitBehaviorByNodeId,
    node_type_analyzer: *NodeTypeAnalyzer,
    diagnostic_store: *diagnostics.DiagnosticStore,
    source_registry: *sources.SourceRegistry,
};

pub fn setupNodeTypeAnalyzerFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !NodeTypeAnalyzerFixture {
    return setupNodeTypeAnalyzerFixtureFromSourceFiles(arena_state, &.{.{ .path = "main.mt", .source = source }});
}

pub fn setupNodeTypeAnalyzerFixtureFromSourceFiles(
    arena_state: *std.heap.ArenaAllocator,
    source_files: []const sources.SourceFile,
) !NodeTypeAnalyzerFixture {
    const name_resolver_fixture = try setupNameResolverFixtureFromSourceFiles(arena_state, source_files);
    const resolved_program = try name_resolver_fixture.resolver.resolveProgram(&name_resolver_fixture.program);

    var control_flow_validator = ControlFlowValidator.init(
        StructuralValidator.init(name_resolver_fixture.diagnostic_store),
        ExitBehaviorAnalyzer.init(arena_state.allocator(), name_resolver_fixture.diagnostic_store),
    );
    const exit_behavior_by_node_id = try control_flow_validator.validateProgram(&name_resolver_fixture.program);

    const node_type_analyzer = try arena_state.allocator().create(NodeTypeAnalyzer);
    node_type_analyzer.* = try NodeTypeAnalyzer.init(arena_state.allocator(), name_resolver_fixture.diagnostic_store);

    return .{
        .resolved_program = resolved_program,
        .exit_behavior_by_node_id = exit_behavior_by_node_id,
        .node_type_analyzer = node_type_analyzer,
        .diagnostic_store = name_resolver_fixture.diagnostic_store,
        .source_registry = name_resolver_fixture.source_registry,
    };
}
