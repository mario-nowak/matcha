const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const StructuralValidator = @import("semantic_analysis").control_flow_validation.StructuralValidator;
const setupParserFixture = @import("parser_helpers.zig").setupParserFixture;

const StructuralValidatorFixture = struct {
    program: ast.Program,
    validator: *StructuralValidator,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupStructuralValidatorFixture(
    arena_state: *std.heap.ArenaAllocator,
    source: []const u8,
) !StructuralValidatorFixture {
    const arena = arena_state.allocator();
    const parser_fixture = try setupParserFixture(arena_state, source);
    const module = try parser_fixture.parser.parse(parser_fixture.lexer.*);
    const program = ast.Program{ .modules = try arena.dupe(ast.Module, &.{module}) };
    const validator = try arena.create(StructuralValidator);
    validator.* = StructuralValidator.init(parser_fixture.diagnostic_store);

    return .{
        .program = program,
        .validator = validator,
        .diagnostic_store = parser_fixture.diagnostic_store,
    };
}
