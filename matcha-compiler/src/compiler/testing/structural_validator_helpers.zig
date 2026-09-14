const std = @import("std");
const ast = @import("ast");
const diagnostics = @import("diagnostics");
const StructuralValidator = @import("semantic_analysis").control_flow_validation.StructuralValidator;
const setupParserPipeline = @import("parser_helpers.zig").setupParserPipeline;

const StructuralValidatorFixture = struct {
    program: ast.Program,
    validator: *StructuralValidator,
    diagnostic_store: *diagnostics.DiagnosticStore,
};

pub fn setupStructuralValidatorFixture(
    arena: *std.heap.ArenaAllocator,
    source: []const u8,
) !StructuralValidatorFixture {
    const allocator = arena.allocator();
    const parser_pipeline = try setupParserPipeline(arena, source);
    const program = try parser_pipeline.parser.parse();
    const validator = try allocator.create(StructuralValidator);
    validator.* = StructuralValidator.init(parser_pipeline.diagnostic_store);

    return .{
        .program = program,
        .validator = validator,
        .diagnostic_store = parser_pipeline.diagnostic_store,
    };
}
