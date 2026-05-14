const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");

const node_type_analyzer = @import("node_type_analyzer.zig");
const type_checking_types = @import("type_checking_types.zig");

pub const TypeError = type_checking_types.TypeError;

pub const TypeSeeder = struct {
    pub fn init() @This() {
        return .{};
    }

    pub fn seedProgram(
        self: *@This(),
        analyzer: *node_type_analyzer.NodeTypeAnalyzer,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        try self.seedModuleLevelItemTypes(analyzer, resolved_program);
    }

    fn seedModuleLevelItemTypes(
        self: *@This(),
        analyzer: *node_type_analyzer.NodeTypeAnalyzer,
        resolved_program: *const symbols.ResolvedProgram,
    ) TypeError!void {
        var resolved_structures_iterator = resolved_program.resolved_structure_by_symbol_id.valueIterator();
        while (resolved_structures_iterator.next()) |structure| {
            const structure_type_id: typing.StructureTypeId = @intCast(analyzer.type_store.structure_types.items.len);
            analyzer.type_store.structure_types.append(analyzer.allocator, .{
                .symbol_id = structure.symbol_id,
                .name = structure.name,
                .fields = &.{},
                .field_index_by_name = std.StringHashMap(u32).init(analyzer.allocator),
                .function_symbol_id_by_name = std.StringHashMap(symbols.SymbolId).init(analyzer.allocator),
            }) catch unreachable;
            const type_id = analyzer.type_store.addType(.{ .Structure = structure_type_id });
            analyzer.type_by_symbol_id.put(structure.symbol_id, type_id) catch unreachable;
        }

        var resolved_functions_iterator = resolved_program.resolved_function_by_symbol_id.valueIterator();
        while (resolved_functions_iterator.next()) |function| {
            self.seedFunctionTypes(analyzer, function.*);
        }

        resolved_structures_iterator = resolved_program.resolved_structure_by_symbol_id.valueIterator();
        while (resolved_structures_iterator.next()) |structure| {
            const type_id = analyzer.type_by_symbol_id.get(structure.symbol_id).?;
            const structure_type_id = switch (analyzer.type_store.getType(type_id)) {
                .Structure => |id| id,
                else => unreachable,
            };

            var fields = std.ArrayList(typing.Field){};
            var field_index_by_name = std.StringHashMap(u32).init(analyzer.allocator);
            var function_symbol_id_by_name = std.StringHashMap(symbols.SymbolId).init(analyzer.allocator);
            for (structure.fields, 0..) |field, index| {
                fields.append(analyzer.allocator, .{
                    .name = field.name,
                    .type_id = analyzer.resolveTypeReference(field.type_reference),
                }) catch unreachable;
                field_index_by_name.put(field.name, @intCast(index)) catch unreachable;
            }
            for (structure.function_symbol_ids) |function_symbol_id| {
                const function_symbol = resolved_program.symbol_table.getSymbol(function_symbol_id);
                function_symbol_id_by_name.put(function_symbol.name, function_symbol_id) catch unreachable;
            }

            analyzer.type_store.structure_types.items[structure_type_id] = .{
                .symbol_id = structure.symbol_id,
                .name = structure.name,
                .fields = fields.toOwnedSlice(analyzer.allocator) catch unreachable,
                .field_index_by_name = field_index_by_name,
                .function_symbol_id_by_name = function_symbol_id_by_name,
            };
        }
    }

    fn seedFunctionTypes(
        self: *@This(),
        analyzer: *node_type_analyzer.NodeTypeAnalyzer,
        function: symbols.ResolvedFunction,
    ) void {
        _ = self;
        var parameter_types = std.ArrayList(typing.TypeId){};
        for (function.parameters) |parameter| {
            parameter_types.append(analyzer.allocator, analyzer.resolveTypeReference(parameter.type_reference)) catch unreachable;
        }

        const owned_parameter_types = parameter_types.toOwnedSlice(analyzer.allocator) catch unreachable;
        const function_return_type = analyzer.resolveTypeReference(function.return_type_reference);
        const function_type_id = analyzer.type_store.addFunctionType(.{
            .parameter_types = owned_parameter_types,
            .return_type = function_return_type,
        });
        analyzer.type_by_symbol_id.put(function.symbol_id, function_type_id) catch unreachable;
        for (function.parameters, owned_parameter_types) |parameter, parameter_type| {
            analyzer.type_by_symbol_id.put(parameter.symbol_id, parameter_type) catch unreachable;
        }
    }
};
