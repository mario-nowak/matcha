const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");
const lowering = @import("lowering");

const runtime_symbols = @import("runtime_symbols");
const emission = @import("emission");
const structure_type_renderer_module = @import("structure_type_renderer.zig");

const RuntimeSymbolRenderer = @import("runtime_symbol_renderer.zig").RuntimeSymbolRenderer;
const RuntimeCallEmitter = emission.RuntimeCallEmitter;
const StringLiteralPool = emission.StringLiteralPool;
const StringLiteralRenderer = @import("string_literal_renderer.zig").StringLiteralRenderer;
const StructureTypeRenderer = structure_type_renderer_module.StructureTypeRenderer;
const FunctionEmitter = emission.FunctionEmitter;
const UnionTypeRenderer = @import("union_type_renderer.zig").UnionTypeRenderer;

const LlvmTypeDefinition = struct {
    name: []const u8,
    types: []const u8,
};

pub const LlvmModuleRenderer = struct {
    allocator: std.mem.Allocator,
    target_triple: []const u8,
    function_emitter: *FunctionEmitter,
    runtime_call_emitter: *RuntimeCallEmitter,
    runtime_symbol_renderer: *const RuntimeSymbolRenderer,
    string_literal_pool: *StringLiteralPool,
    string_literal_renderer: *StringLiteralRenderer,
    structure_type_renderer: *StructureTypeRenderer,
    union_type_renderer: *UnionTypeRenderer,
    llvm_matcha_type_by_type_id: std.AutoHashMap(typing.TypeId, LlvmTypeDefinition),

    pub fn init(
        allocator: std.mem.Allocator,
        target_triple: []const u8,
        function_emitter: *FunctionEmitter,
        runtime_call_emitter: *RuntimeCallEmitter,
        runtime_symbol_renderer: *const RuntimeSymbolRenderer,
        string_literal_pool: *StringLiteralPool,
        string_literal_renderer: *StringLiteralRenderer,
        structure_type_renderer: *StructureTypeRenderer,
        union_type_renderer: *UnionTypeRenderer,
    ) @This() {
        return .{
            .allocator = allocator,
            .target_triple = target_triple,
            .function_emitter = function_emitter,
            .runtime_call_emitter = runtime_call_emitter,
            .runtime_symbol_renderer = runtime_symbol_renderer,
            .string_literal_pool = string_literal_pool,
            .string_literal_renderer = string_literal_renderer,
            .structure_type_renderer = structure_type_renderer,
            .union_type_renderer = union_type_renderer,
            .llvm_matcha_type_by_type_id = std.AutoHashMap(typing.TypeId, LlvmTypeDefinition).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.llvm_matcha_type_by_type_id.deinit();
    }

    pub fn renderLlvmIr(self: *@This(), lowered_program: *const lowering.LoweredProgram) ![]const u8 {
        self.resetModuleState();

        const structure_type_definitions = self.structure_type_renderer.renderStructureTypeDefinitions(lowered_program);
        const union_type_definitions = try self.union_type_renderer.renderUnionTypeDefinitions(lowered_program);
        var user_defined_functions = self.renderTopLevelFunctionDefinitions(lowered_program);
        defer user_defined_functions.deinit(self.allocator);
        var owned_functions = self.renderOwnedFunctionDefinitions(lowered_program);
        defer owned_functions.deinit(self.allocator);
        const main_function_ir = self.function_emitter.emitMainFunction(lowered_program);

        return self.renderModule(
            structure_type_definitions,
            union_type_definitions,
            user_defined_functions.items,
            owned_functions.items,
            main_function_ir,
        );
    }

    fn renderTopLevelFunctionDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) std.ArrayList([]const u8) {
        var user_defined_functions = std.ArrayList([]const u8){};
        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.definition) {
                    .Function => |function_definition| {
                        const function_ir = self.function_emitter.emitFunctionDefinition(
                            statement.id,
                            &function_definition,
                            lowered_program,
                        );
                        user_defined_functions.append(self.allocator, function_ir) catch unreachable;
                    },
                    .Structure => {},
                    .Union => {},
                },
                else => {},
            }
        }

        return user_defined_functions;
    }

    fn renderModule(
        self: *@This(),
        structure_type_definitions: []const u8,
        union_type_definitions: []const u8,
        user_defined_functions: []const []const u8,
        owned_functions: []const []const u8,
        main_function_ir: []const u8,
    ) ![]const u8 {
        var sections = std.ArrayList([]const u8){};
        defer sections.deinit(self.allocator);
        try sections.append(self.allocator, self.renderModulePreamble());
        if (structure_type_definitions.len > 0) {
            sections.append(self.allocator, structure_type_definitions) catch unreachable;
        }
        if (union_type_definitions.len > 0) {
            try sections.append(self.allocator, union_type_definitions);
        }
        for (user_defined_functions) |function_ir| {
            sections.append(self.allocator, function_ir) catch unreachable;
        }
        for (owned_functions) |function_ir| {
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
        self.runtime_call_emitter.reset();
    }

    fn renderModulePreamble(self: *@This()) []const u8 {
        var module_preamble_buffer = std.ArrayList(u8){};
        defer module_preamble_buffer.deinit(self.allocator);

        const runtime_symbol_declarations = self.runtime_symbol_renderer.renderDeclarations(self.runtime_call_emitter.runtime_requirements);
        module_preamble_buffer.writer(self.allocator).print(
            "target triple = \"{s}\"\n\n{s}\n\n{s}\n{s}",
            .{ self.target_triple, runtime_symbol_declarations, lowering.llvm_type.string_llvm_type_definition, lowering.llvm_type.array_llvm_type_definition },
        ) catch unreachable;

        const string_literal_globals_ir = self.string_literal_renderer.renderGlobals(self.string_literal_pool);
        if (string_literal_globals_ir.len > 0) {
            module_preamble_buffer.writer(self.allocator).print("\n\n{s}", .{string_literal_globals_ir}) catch unreachable;
        }
        return std.fmt.allocPrint(self.allocator, "{s}", .{module_preamble_buffer.items}) catch unreachable;
    }

    /// Renders the functions that a type declares in its body.
    fn renderOwnedFunctionDefinitions(
        self: *@This(),
        lowered_program: *const lowering.LoweredProgram,
    ) std.ArrayList([]const u8) {
        var owned_function_definitions = std.ArrayList([]const u8){};

        for (lowered_program.analyzed_program.resolved_program.program.statements) |*statement| {
            const function_definitions = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.definition) {
                    inline .Structure, .Union => |type_definition| type_definition.function_definitions,
                    else => continue,
                },
                else => continue,
            };
            self.appendOwnedFunctionDefinitions(
                &owned_function_definitions,
                function_definitions,
                lowered_program,
            );
        }

        return owned_function_definitions;
    }

    fn appendOwnedFunctionDefinitions(
        self: *@This(),
        owned_function_definitions: *std.ArrayList([]const u8),
        function_definitions: []const ast.Node,
        lowered_program: *const lowering.LoweredProgram,
    ) void {
        for (function_definitions) |function_definition_node| {
            const function_definition = switch (function_definition_node.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.definition) {
                    .Function => |function| function,
                    else => unreachable,
                },
                else => unreachable,
            };
            const function_definition_emission = self.function_emitter.emitFunctionDefinition(
                function_definition_node.id,
                &function_definition,
                lowered_program,
            );
            owned_function_definitions.append(self.allocator, function_definition_emission) catch unreachable;
        }
    }
};
