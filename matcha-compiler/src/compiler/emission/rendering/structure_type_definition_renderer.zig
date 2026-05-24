const std = @import("std");
const symbols = @import("symbols");
const lowering = @import("lowering");

const llvm_type_lowering = lowering.llvm_type;

pub const StructureTypeDefinitionRenderer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
        };
    }

    pub fn emitStructureTypeDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) []const u8 {
        var structure_definitions_buffer = std.ArrayList(u8){};
        defer structure_definitions_buffer.deinit(self.allocator);

        var has_structure_definition = false;
        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            _ = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Structure => |structure| structure,
                    else => continue,
                },
                else => continue,
            };

            const structure_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(statement.id) orelse unreachable;
            const resolved_structure = lowered_program.analyzed_program.resolved_program.resolved_structure_by_symbol_id.get(structure_symbol_id) orelse unreachable;

            if (has_structure_definition) {
                structure_definitions_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
            structure_definitions_buffer.writer(self.allocator).print(
                "{s}",
                .{self.emitStructureTypeDefinition(resolved_structure, lowered_program)},
            ) catch unreachable;
            has_structure_definition = true;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{structure_definitions_buffer.items}) catch unreachable;
    }

    fn emitStructureTypeDefinition(
        self: *@This(),
        resolved_structure: symbols.ResolvedStructure,
        lowered_program: *const lowering.LoweredProgram,
    ) []const u8 {
        const structure_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(resolved_structure.symbol_id);
        const structure_llvm_type_name = self.generateStructureName(structure_symbol);

        var structure_definition_buffer = std.ArrayList(u8){};
        defer structure_definition_buffer.deinit(self.allocator);

        structure_definition_buffer.writer(self.allocator).print(
            "%{s} = type {{",
            .{structure_llvm_type_name},
        ) catch unreachable;
        for (resolved_structure.fields, 0..) |field, index| {
            if (index == 0) {
                structure_definition_buffer.writer(self.allocator).print(" ", .{}) catch unreachable;
            } else {
                structure_definition_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            const field_type_id = llvm_type_lowering.typeIdFromResolvedTypeReference(lowered_program.analyzed_program, field.type_reference);
            structure_definition_buffer.writer(self.allocator).print(
                "{s}",
                .{lowered_program.llvmIrType(field_type_id)},
            ) catch unreachable;
        }
        if (resolved_structure.fields.len > 0) {
            structure_definition_buffer.writer(self.allocator).print(" ", .{}) catch unreachable;
        }
        structure_definition_buffer.writer(self.allocator).print("}}", .{}) catch unreachable;

        return std.fmt.allocPrint(self.allocator, "{s}", .{structure_definition_buffer.items}) catch unreachable;
    }

    fn generateStructureName(self: *@This(), symbol: symbols.Symbol) []const u8 {
        switch (symbol.kind) {
            .Structure => return std.fmt.allocPrint(
                self.allocator,
                "matcha_structure_{d}_{s}",
                .{ symbol.id, symbol.name },
            ) catch unreachable,
            else => unreachable,
        }
    }
};
