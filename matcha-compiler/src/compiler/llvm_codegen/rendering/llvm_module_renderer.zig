const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const runtime_symbols = @import("runtime_symbols");
const emission = @import("emission");
const structure_type_renderer_module = @import("structure_type_renderer.zig");

const RuntimeSymbolRenderer = @import("runtime_symbol_renderer.zig").RuntimeSymbolRenderer;
const StringLiteralPool = emission.StringLiteralPool;
const StringLiteralRenderer = @import("string_literal_renderer.zig").StringLiteralRenderer;
const StructureTypeRenderer = structure_type_renderer_module.StructureTypeRenderer;
const FunctionEmitter = emission.FunctionEmitter;

// A string is a header containing a pointer to the data and the length.
const llvm_string_type_definition = "%String = type { i8*, i64 }";
// An array is a header containing the length, capacity, and a pointer to the data.
const llvm_array_type_definition = "%Array = type { i64, i64, ptr }";

const LlvmTypeDefinition = struct {
    name: []const u8,
    types: []const u8,
};

pub const LlvmModuleRenderer = struct {
    allocator: std.mem.Allocator,
    target_triple: []const u8,
    function_emitter: *FunctionEmitter,
    runtime_symbol_renderer: *const RuntimeSymbolRenderer,
    string_literal_pool: *StringLiteralPool,
    string_literal_renderer: *StringLiteralRenderer,
    structure_type_renderer: *StructureTypeRenderer,
    llvm_matcha_type_by_type_id: std.AutoHashMap(typing.TypeId, LlvmTypeDefinition),

    pub fn init(
        allocator: std.mem.Allocator,
        target_triple: []const u8,
        function_emitter: *FunctionEmitter,
        runtime_symbol_renderer: *const RuntimeSymbolRenderer,
        string_literal_pool: *StringLiteralPool,
        string_literal_renderer: *StringLiteralRenderer,
        structure_type_renderer: *StructureTypeRenderer,
    ) @This() {
        return .{
            .allocator = allocator,
            .target_triple = target_triple,
            .function_emitter = function_emitter,
            .runtime_symbol_renderer = runtime_symbol_renderer,
            .string_literal_pool = string_literal_pool,
            .string_literal_renderer = string_literal_renderer,
            .structure_type_renderer = structure_type_renderer,
            .llvm_matcha_type_by_type_id = std.AutoHashMap(typing.TypeId, LlvmTypeDefinition).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_matcha_type_by_type_id.deinit();
    }

    pub fn renderLlvmIr(self: *@This(), lowered_program: *const lowering.LoweredProgram) []const u8 {
        self.resetModuleState();

        const structure_type_definitions = self.structure_type_renderer.renderStructureTypeDefinitions(lowered_program);
        var user_defined_functions = self.renderTopLevelFunctionDefinitions(lowered_program);
        defer user_defined_functions.deinit(self.allocator);
        var structure_method_functions = self.renderStructureMethodFunctionDefinitions(lowered_program);
        defer structure_method_functions.deinit(self.allocator);
        const main_function_ir = self.function_emitter.emitMainFunction(lowered_program);

        return self.renderModule(
            structure_type_definitions,
            user_defined_functions.items,
            structure_method_functions.items,
            main_function_ir,
            lowered_program,
        );
    }

    fn renderTopLevelFunctionDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) std.ArrayList([]const u8) {
        var user_defined_functions = std.ArrayList([]const u8){};
        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function_definition| {
                        const function_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(
                            statement.id,
                        ) orelse unreachable;
                        const resolved_function = lowered_program.analyzed_program.resolved_program.resolved_function_by_symbol_id.get(
                            function_symbol_id,
                        ) orelse unreachable;
                        const function_ir = self.function_emitter.emitFunctionDefinition(
                            statement.id,
                            &function_definition,
                            &resolved_function,
                            null,
                            lowered_program,
                        );
                        user_defined_functions.append(self.allocator, function_ir) catch unreachable;
                    },
                    .Structure => {},
                },
                else => {},
            }
        }

        return user_defined_functions;
    }

    fn renderModule(
        self: *@This(),
        user_defined_types: []const u8,
        user_defined_functions: []const []const u8,
        structure_method_functions: []const []const u8,
        main_function_ir: []const u8,
        lowered_program: *const lowering.LoweredProgram,
    ) []const u8 {
        var sections = std.ArrayList([]const u8){};
        defer sections.deinit(self.allocator);
        sections.append(self.allocator, self.renderModulePreamble(lowered_program)) catch unreachable;
        if (user_defined_types.len > 0) {
            sections.append(self.allocator, user_defined_types) catch unreachable;
        }
        for (user_defined_functions) |function_ir| {
            sections.append(self.allocator, function_ir) catch unreachable;
        }
        for (structure_method_functions) |function_ir| {
            sections.append(self.allocator, function_ir) catch unreachable;
        }
        sections.append(self.allocator, main_function_ir) catch unreachable;

        var module_buffer = std.ArrayList(u8){};
        defer module_buffer.deinit(self.allocator);
        for (sections.items, 0..) |section, index| {
            module_buffer.writer(self.allocator).print("{s}", .{section}) catch unreachable;
            if (index + 1 < sections.items.len) {
                module_buffer.writer(self.allocator).print("\n\n", .{}) catch unreachable;
            }
        }
        module_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;

        return std.fmt.allocPrint(self.allocator, "{s}", .{module_buffer.items}) catch unreachable;
    }

    fn resetModuleState(self: *@This()) void {
        self.string_literal_pool.reset();
    }

    fn renderModulePreamble(self: *@This(), lowered_program: *const lowering.LoweredProgram) []const u8 {
        var module_preamble_buffer = std.ArrayList(u8){};
        defer module_preamble_buffer.deinit(self.allocator);

        const runtime_symbol_declarations = self.runtime_symbol_renderer.renderDeclarations(runtimeRequirementsFromPlan(lowered_program.runtime_requirements_plan));
        module_preamble_buffer.writer(self.allocator).print(
            "target triple = \"{s}\"\n\n{s}\n\n{s}\n{s}",
            .{ self.target_triple, runtime_symbol_declarations, llvm_string_type_definition, llvm_array_type_definition },
        ) catch unreachable;

        const string_literal_globals_ir = self.string_literal_renderer.renderGlobals(self.string_literal_pool);
        if (string_literal_globals_ir.len > 0) {
            module_preamble_buffer.writer(self.allocator).print("\n\n{s}", .{string_literal_globals_ir}) catch unreachable;
        }
        return std.fmt.allocPrint(self.allocator, "{s}", .{module_preamble_buffer.items}) catch unreachable;
    }

    fn runtimeRequirementsFromPlan(plan: lowering.lowering_types.RuntimeRequirementsPlan) runtime_symbols.RuntimeRequirements {
        return .{
            .print_int = plan.print_int,
            .print_string = plan.print_string,
            .read_file = plan.read_file,
            .read_line = plan.read_line,
            .get_arguments = plan.get_arguments,
            .string_concatenate = plan.string_concatenate,
            .string_compare = plan.string_compare,
            .string_trim = plan.string_trim,
            .string_split = plan.string_split,
            .string_to_int = plan.string_to_int,
            .int_to_string = plan.int_to_string,
            .panic_index_out_of_bounds = plan.panic_index_out_of_bounds,
            .array_append_slot = plan.array_append_slot,
        };
    }

    fn renderStructureMethodFunctionDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) std.ArrayList([]const u8) {
        var method_definitions = std.ArrayList([]const u8){};

        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            const structure_definition = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Structure => |structure| structure,
                    else => continue,
                },
                else => continue,
            };

            const structure_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(statement.id) orelse unreachable;
            const structure_symbol = lowered_program.analyzed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id);
            self.appendStructureMethodDefinitions(
                &method_definitions,
                structure_definition,
                structure_symbol,
                lowered_program,
            );
        }

        return method_definitions;
    }

    fn appendStructureMethodDefinitions(
        self: *@This(),
        method_definitions: *std.ArrayList([]const u8),
        structure_definition: ast.Structure,
        structure_symbol: symbols.Symbol,
        lowered_program: *const lowering.LoweredProgram,
    ) void {
        for (structure_definition.function_definitions) |function_definition_node| {
            const function_definition = switch (function_definition_node.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function| function,
                    else => unreachable,
                },
                else => unreachable,
            };
            const function_symbol_id = lowered_program.analyzed_program.resolved_program.symbol_id_by_node_id.get(
                function_definition_node.id,
            ) orelse unreachable;
            const resolved_function = lowered_program.analyzed_program.resolved_program.resolved_function_by_symbol_id.get(function_symbol_id) orelse unreachable;
            const function_definition_emission = self.function_emitter.emitFunctionDefinition(
                function_definition_node.id,
                &function_definition,
                &resolved_function,
                structure_symbol,
                lowered_program,
            );
            method_definitions.append(self.allocator, function_definition_emission) catch unreachable;
        }
    }
};
