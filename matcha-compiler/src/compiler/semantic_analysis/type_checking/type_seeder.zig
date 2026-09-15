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
        var structure_shell_iterator = resolved_program.symbol_table.iterator();
        while (structure_shell_iterator.next()) |symbol| {
            switch (symbol.kind) {
                .Structure => {},
                else => continue,
            }
            const structure_type_id: typing.StructureTypeId = @intCast(analyzer.type_store.structure_types.items.len);
            analyzer.type_store.structure_types.append(analyzer.allocator, .{
                .symbol_id = symbol.id,
                .name = symbol.name,
                .fields = &.{},
                .field_index_by_name = std.StringHashMap(u32).init(analyzer.allocator),
                .function_symbol_id_by_name = std.StringHashMap(symbols.SymbolId).init(analyzer.allocator),
            }) catch unreachable;
            const type_id = analyzer.type_store.addType(.{ .Structure = structure_type_id });
            analyzer.type_by_symbol_id.put(symbol.id, type_id) catch unreachable;
        }

        var function_iterator = resolved_program.symbol_table.iterator();
        while (function_iterator.next()) |symbol| {
            switch (symbol.kind) {
                .Function => |function_information| self.seedFunctionTypes(analyzer, symbol.id, function_information, resolved_program),
                else => {},
            }
        }

        var structure_member_iterator = resolved_program.symbol_table.iterator();
        while (structure_member_iterator.next()) |symbol| {
            const structure_information = switch (symbol.kind) {
                .Structure => |structure_information| structure_information,
                else => continue,
            };
            const type_id = analyzer.type_by_symbol_id.get(symbol.id).?;
            const structure_type_id = switch (analyzer.type_store.getType(type_id)) {
                .Structure => |id| id,
                else => unreachable,
            };

            var fields = std.ArrayList(typing.Field){};
            var field_index_by_name = std.StringHashMap(u32).init(analyzer.allocator);
            var function_symbol_id_by_name = std.StringHashMap(symbols.SymbolId).init(analyzer.allocator);
            for (structure_information.fields, 0..) |field, index| {
                fields.append(analyzer.allocator, .{
                    .name = field.name,
                    .type_id = analyzer.resolveTypeReference(field.type_reference),
                }) catch unreachable;
                field_index_by_name.put(field.name, @intCast(index)) catch unreachable;
            }
            for (structure_information.function_symbol_ids) |function_symbol_id| {
                const function_symbol = resolved_program.symbol_table.getSymbol(function_symbol_id);
                function_symbol_id_by_name.put(function_symbol.name, function_symbol_id) catch unreachable;
            }

            analyzer.type_store.structure_types.items[structure_type_id] = .{
                .symbol_id = symbol.id,
                .name = symbol.name,
                .fields = fields.toOwnedSlice(analyzer.allocator) catch unreachable,
                .field_index_by_name = field_index_by_name,
                .function_symbol_id_by_name = function_symbol_id_by_name,
            };
        }
    }

    fn seedFunctionTypes(
        self: *@This(),
        analyzer: *node_type_analyzer.NodeTypeAnalyzer,
        function_symbol_id: symbols.SymbolId,
        function_information: symbols.FunctionSymbolInformation,
        resolved_program: *const symbols.ResolvedProgram,
    ) void {
        _ = self;
        var parameter_types = std.ArrayList(typing.TypeId){};
        for (function_information.parameter_symbol_ids) |parameter_symbol_id| {
            const parameter_type_reference = parameterTypeReference(resolved_program, parameter_symbol_id);
            parameter_types.append(analyzer.allocator, analyzer.resolveTypeReference(parameter_type_reference)) catch unreachable;
        }

        const owned_parameter_types = parameter_types.toOwnedSlice(analyzer.allocator) catch unreachable;
        const function_return_type = analyzer.resolveTypeReference(function_information.return_type_reference);
        const function_type_id = analyzer.type_store.addFunctionType(.{
            .parameter_types = owned_parameter_types,
            .return_type = function_return_type,
        });
        analyzer.type_by_symbol_id.put(function_symbol_id, function_type_id) catch unreachable;
        for (function_information.parameter_symbol_ids, owned_parameter_types) |parameter_symbol_id, parameter_type| {
            analyzer.type_by_symbol_id.put(parameter_symbol_id, parameter_type) catch unreachable;
        }
    }

    fn parameterTypeReference(
        resolved_program: *const symbols.ResolvedProgram,
        parameter_symbol_id: symbols.SymbolId,
    ) symbols.ResolvedTypeReference {
        return switch (resolved_program.symbol_table.getSymbol(parameter_symbol_id).kind) {
            .Binding => |binding_information| binding_information.declared_type_reference orelse unreachable,
            else => unreachable,
        };
    }
};
