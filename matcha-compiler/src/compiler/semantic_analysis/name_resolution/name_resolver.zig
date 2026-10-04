const std = @import("std");
const ast = @import("ast");
const lexing = @import("lexing");
const diagnostics = @import("diagnostics");
const CompileError = diagnostics.CompileError;
const symbols = @import("symbols");
const type_expressions = @import("type_expressions");
const scope = @import("scope.zig");

const ModuleShadowing = enum {
    forbidden,
    allowed,
};

const ResolutionOptions = struct {
    module_shadowing: ModuleShadowing,
};

const ResolutionEnvironment = struct {
    node_scope: *scope.Scope,
    module_scope: *scope.ModuleScope,
    options: ResolutionOptions,
};

pub const NameResolver = struct {
    arena: std.mem.Allocator,
    diagnostic_store: *diagnostics.DiagnosticStore,
    symbol_table: symbols.SymbolTable,
    symbol_id_by_node_id: symbols.SymbolIdByNodeId,

    pub fn init(arena: std.mem.Allocator, diagnostic_store: *diagnostics.DiagnosticStore) @This() {
        return .{
            .arena = arena,
            .diagnostic_store = diagnostic_store,
            .symbol_table = symbols.SymbolTable.init(arena),
            .symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(arena),
        };
    }

    pub fn resolveProgram(self: *@This(), program: *const ast.Program) !symbols.ResolvedProgram {
        return try self.resolveModule(program);
    }

    fn resolveModule(self: *@This(), program: *const ast.Program) !symbols.ResolvedProgram {
        var root_scope = scope.Scope.init(self.arena, null);
        self.symbol_table = symbols.SymbolTable.init(self.arena);
        self.symbol_id_by_node_id = symbols.SymbolIdByNodeId.init(self.arena);

        var module_scope = try self.buildModuleScope(program);

        const root_environment = ResolutionEnvironment{
            .node_scope = &root_scope,
            .module_scope = &module_scope,
            .options = .{
                .module_shadowing = .forbidden,
            },
        };
        for (program.statements) |*statement| {
            try self.resolveNode(statement, root_environment);
        }

        self.symbol_table.assertAllFinalized();
        return .{
            .program = program.*,
            .symbol_id_by_node_id = self.symbol_id_by_node_id,
            .symbol_table = self.symbol_table,
        };
    }

    fn addBuiltinFunctions(self: *@This(), module_scope: *scope.ModuleScope) !void {
        try self.addPrintIntBuiltinDebuggingFunction(module_scope);
        try self.addPrintStringBuiltinDebuggingFunction(module_scope);
        try self.addReadFileBuiltinFunction(module_scope);
        try self.addReadLineBuiltinFunction(module_scope);
        try self.addGetArgumentsBuiltinFunction(module_scope);
    }

    fn addPrintIntBuiltinDebuggingFunction(self: *@This(), module_scope: *scope.ModuleScope) !void {
        const parameter_id = try self.symbol_table.insertSymbol(.{
            .name = "value",
            .declared_at = null,
            .kind = .{ .binding = .{
                .binding_mutability = .immutable,
                .declared_type_reference = .{ .builtin = .integer },
            } },
        });
        const function_id = try self.symbol_table.insertSymbol(.{
            .name = "printInt",
            .declared_at = null,
            .kind = .{ .function = .{
                .parameter_symbol_ids = try self.arena.dupe(symbols.SymbolId, &.{parameter_id}),
                .return_type_reference = .{ .builtin = .unit },
                .implementation_kind = .builtin_print_int,
            } },
        });
        try module_scope.insertSymbol("printInt", function_id);
    }

    fn addPrintStringBuiltinDebuggingFunction(self: *@This(), module_scope: *scope.ModuleScope) !void {
        const parameter_id = try self.symbol_table.insertSymbol(.{
            .name = "value",
            .declared_at = null,
            .kind = .{ .binding = .{
                .binding_mutability = .immutable,
                .declared_type_reference = .{ .builtin = .string },
            } },
        });
        const function_id = try self.symbol_table.insertSymbol(.{
            .name = "printString",
            .declared_at = null,
            .kind = .{ .function = .{
                .parameter_symbol_ids = try self.arena.dupe(symbols.SymbolId, &.{parameter_id}),
                .return_type_reference = .{ .builtin = .unit },
                .implementation_kind = .builtin_print_string,
            } },
        });
        try module_scope.insertSymbol("printString", function_id);
    }

    fn addReadFileBuiltinFunction(self: *@This(), module_scope: *scope.ModuleScope) !void {
        const parameter_id = try self.symbol_table.insertSymbol(.{
            .name = "path",
            .declared_at = null,
            .kind = .{ .binding = .{
                .binding_mutability = .immutable,
                .declared_type_reference = .{ .builtin = .string },
            } },
        });
        const function_id = try self.symbol_table.insertSymbol(.{
            .name = "readFile",
            .declared_at = null,
            .kind = .{ .function = .{
                .parameter_symbol_ids = try self.arena.dupe(symbols.SymbolId, &.{parameter_id}),
                .return_type_reference = .{ .builtin = .string },
                .implementation_kind = .builtin_read_file,
            } },
        });
        try module_scope.insertSymbol("readFile", function_id);
    }

    fn addReadLineBuiltinFunction(self: *@This(), module_scope: *scope.ModuleScope) !void {
        const function_id = try self.symbol_table.insertSymbol(.{
            .name = "readLine",
            .declared_at = null,
            .kind = .{ .function = .{
                .parameter_symbol_ids = &.{},
                .return_type_reference = .{ .builtin = .string },
                .implementation_kind = .builtin_read_line,
            } },
        });
        try module_scope.insertSymbol("readLine", function_id);
    }

    fn addGetArgumentsBuiltinFunction(self: *@This(), module_scope: *scope.ModuleScope) !void {
        const string_type_reference = try self.arena.create(symbols.ResolvedTypeReference);
        string_type_reference.* = .{ .builtin = .string };
        const function_id = try self.symbol_table.insertSymbol(.{
            .name = "getArguments",
            .declared_at = null,
            .kind = .{ .function = .{
                .parameter_symbol_ids = &.{},
                .return_type_reference = .{ .array = string_type_reference },
                .implementation_kind = .builtin_get_arguments,
            } },
        });
        try module_scope.insertSymbol("getArguments", function_id);
    }

    fn buildModuleScope(self: *@This(), program: *const ast.Program) CompileError!scope.ModuleScope {
        var module_scope = scope.ModuleScope.init(self.arena, null);
        // Builtins come first, so the duplicate checks of the module items see them.
        try self.addBuiltinFunctions(&module_scope);

        for (program.statements) |*statement| {
            switch (statement.kind) {
                .item_definition => |item_definition| {
                    try self.registerModuleItemDefinition(statement.id, item_definition, &module_scope);
                },
                else => {},
            }
        }

        return module_scope;
    }

    fn registerModuleItemDefinition(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: ast.ItemDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        switch (item_definition.definition) {
            .function => {
                try self.registerModuleFunctionSymbol(node_id, item_definition, module_scope);
            },
            .structure => {
                try self.registerModuleStructureSymbol(node_id, item_definition, module_scope);
            },
            .@"union" => {
                try self.registerModuleUnionSymbol(node_id, item_definition, module_scope);
            },
        }
    }

    fn registerModuleFunctionSymbol(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: ast.ItemDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        const function_name = item_definition.identifier_token.kind.identifier;
        try self.validateIdentifierIsAvailable(item_definition.identifier_token, function_name, "function");
        module_scope.validateNotInScope(function_name) catch {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, item_definition.identifier_token, "function '{s}' is already defined", .{function_name});
            return error.DiagnosticsEmitted;
        };

        const function_id = try self.symbol_table.insertPreliminarySymbol(.{
            .name = function_name,
            .declared_at = item_definition.item_token,
            .kind = .function,
        });
        try self.symbol_id_by_node_id.put(node_id, function_id);
        try module_scope.insertSymbol(function_name, function_id);
    }

    fn registerModuleStructureSymbol(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: ast.ItemDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        const structure_name = item_definition.identifier_token.kind.identifier;
        try self.validateIdentifierIsAvailable(item_definition.identifier_token, structure_name, "structure");
        module_scope.validateNotInScope(structure_name) catch {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, item_definition.identifier_token, "structure '{s}' is already defined", .{structure_name});
            return error.DiagnosticsEmitted;
        };

        const structure_id = try self.symbol_table.insertPreliminarySymbol(.{
            .name = structure_name,
            .declared_at = item_definition.item_token,
            .kind = .structure,
        });
        try self.symbol_id_by_node_id.put(node_id, structure_id);
        try module_scope.insertSymbol(structure_name, structure_id);
    }

    fn registerModuleUnionSymbol(
        self: *@This(),
        node_id: ast.NodeId,
        item_definition: ast.ItemDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        const union_name = item_definition.identifier_token.kind.identifier;
        try self.validateIdentifierIsAvailable(item_definition.identifier_token, union_name, "union");
        module_scope.validateNotInScope(union_name) catch {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, item_definition.identifier_token, "union '{s}' is already defined", .{union_name});
            return error.DiagnosticsEmitted;
        };

        const union_id = try self.symbol_table.insertPreliminarySymbol(.{
            .name = union_name,
            .declared_at = item_definition.item_token,
            .kind = .@"union",
        });
        try self.symbol_id_by_node_id.put(node_id, union_id);
        try module_scope.insertSymbol(union_name, union_id);
    }

    fn resolveNode(
        self: *@This(),
        node: *const ast.Node,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        switch (node.kind) {
            .binding_declaration => |binding_declaration| try self.resolveBindingDeclarationNode(node.id, binding_declaration, environment),
            .item_definition => |item_definition| try self.resolveItemDefinitionNode(item_definition, environment.module_scope),
            .return_statement => |return_statement| try self.resolveReturnStatementNode(return_statement, environment),
            .assignment_statement => |assignment_statement| try self.resolveAssignmentStatementNode(assignment_statement, environment),
            .loop => |loop| try self.resolveLoopNode(loop, environment),
            .@"while" => |while_statement| try self.resolveWhileNode(while_statement, environment),
            .for_in => |for_in| try self.resolveForInNode(node.id, for_in, environment),
            .call_expression => |call_expression| try self.resolveCallExpressionNode(call_expression, environment),
            .binary_expression => |binary_expression| try self.resolveBinaryExpressionNode(binary_expression, environment),
            .unary_expression => |unary_expression| try self.resolveUnaryExpressionNode(unary_expression, environment),
            .member_expression => |member_expression| try self.resolveMemberExpressionNode(member_expression, environment),
            .identifier => |identifier| try self.resolveIdentifierNode(node.id, identifier, environment),
            .block => |block| try self.resolveBlockNode(block, environment),
            .if_statement => |if_statement| try self.resolveIfStatementNode(if_statement, environment),
            .if_expression => |if_expression| try self.resolveIfExpressionNode(if_expression, environment),
            .match_expression => |match_expression| try self.resolveMatchExpressionNode(match_expression, environment),
            .subjectless_match_expression => |subjectless_match_expression| try self.resolveSubjectlessMatchExpressionNode(subjectless_match_expression, environment),
            .expression_statement => |expression_statement| try self.resolveExpressionStatementNode(expression_statement, environment),
            .qualified_structure_literal => |*qualified_structure_literal| try self.resolveQualifiedStructureLiteral(node.id, qualified_structure_literal, environment),
            .structure_literal => |structure_literal| try self.resolveStructureLiteralNode(structure_literal, environment),
            .array_literal => |array_literal| try self.resolveArrayLiteralNode(array_literal, environment),
            .index_expression => |index_expression| try self.resolveIndexExpressionNode(index_expression, environment),
            .implicit_member_expression,
            .integer_literal,
            .boolean_literal,
            .string_literal,
            .unit_literal,
            .leave_statement,
            .continue_statement,
            => {},
        }
    }

    fn resolveBindingDeclarationNode(
        self: *@This(),
        node_id: ast.NodeId,
        binding_declaration: ast.BindingDeclaration,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        const declaration_name = binding_declaration.name.kind.identifier;
        try self.validateBindingDeclarationName(binding_declaration.name, declaration_name, "value", environment);

        try self.resolveNode(binding_declaration.value, environment);
        const annotated_type_reference = if (binding_declaration.type_annotation) |type_annotation|
            try self.resolveTypeExpression(type_annotation, environment.module_scope)
        else
            null;

        const declaration_id = try self.symbol_table.insertSymbol(.{
            .name = declaration_name,
            .declared_at = binding_declaration.val_token,
            .kind = .{
                .binding = .{
                    .binding_mutability = switch (binding_declaration.binding_mutability) {
                        .mutable => symbols.BindingMutability.mutable,
                        .immutable => symbols.BindingMutability.immutable,
                    },
                    .declared_type_reference = annotated_type_reference,
                },
            },
        });
        try self.symbol_id_by_node_id.put(node_id, declaration_id);
        try environment.node_scope.insertSymbol(declaration_name, declaration_id);
    }

    fn validateBindingDeclarationName(
        self: *@This(),
        declaration_token: lexing.Token,
        declaration_name: []const u8,
        kind_name: []const u8,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.validateIdentifierIsAvailable(declaration_token, declaration_name, kind_name);
        if (environment.options.module_shadowing == .forbidden) {
            if (environment.module_scope.lookupSymbol(declaration_name)) |_| {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, declaration_token, "{s} '{s}' is already declared in module scope", .{ kind_name, declaration_name });
                return error.DiagnosticsEmitted;
            }
        }
        if (environment.node_scope.lookupSymbol(declaration_name)) |_| {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, declaration_token, "{s} '{s}' is already declared in this scope", .{ kind_name, declaration_name });
            return error.DiagnosticsEmitted;
        }
    }

    fn resolveItemDefinitionNode(
        self: *@This(),
        item_definition: ast.ItemDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        switch (item_definition.definition) {
            .function => |function_definition| {
                const function_symbol_id = module_scope.lookupSymbol(item_definition.identifier_token.kind.identifier) orelse unreachable;
                try self.resolveFunction(function_symbol_id, &function_definition, module_scope);
            },
            .structure => |structure_definition| {
                try self.resolveStructureDefinition(item_definition.identifier_token.kind.identifier, &structure_definition, module_scope);
            },
            .@"union" => |union_definition| {
                try self.resolveUnionDefinition(item_definition.identifier_token.kind.identifier, &union_definition, module_scope);
            },
        }
    }

    fn resolveReturnStatementNode(
        self: *@This(),
        return_statement: ast.ReturnStatement,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        if (return_statement.value) |value| {
            try self.resolveNode(value, environment);
        }
    }

    fn resolveAssignmentStatementNode(
        self: *@This(),
        assignment_statement: ast.AssignmentStatement,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(assignment_statement.target, environment);
        try self.resolveNode(assignment_statement.value, environment);
    }

    fn resolveLoopNode(
        self: *@This(),
        loop_statement: ast.Loop,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        var loop_scope = scope.Scope.init(self.arena, environment.node_scope);
        var loop_environment = environment;
        loop_environment.node_scope = &loop_scope;
        try self.resolveNode(loop_statement.body_block, loop_environment);
    }

    fn resolveWhileNode(
        self: *@This(),
        while_statement: ast.While,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(while_statement.condition, environment);
        if (while_statement.update) |update| {
            try self.resolveNode(update, environment);
        }

        var loop_scope = scope.Scope.init(self.arena, environment.node_scope);
        var loop_environment = environment;
        loop_environment.node_scope = &loop_scope;
        try self.resolveNode(while_statement.body_block, loop_environment);
    }

    fn resolveForInNode(
        self: *@This(),
        node_id: ast.NodeId,
        for_in: ast.ForIn,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(for_in.iterable, environment);

        var loop_scope = scope.Scope.init(self.arena, environment.node_scope);
        const item_name = for_in.item_name.kind.identifier;
        try self.validateBindingDeclarationName(for_in.item_name, item_name, "for-in binding", environment);
        const item_symbol_id = try self.symbol_table.insertSymbol(.{
            .name = item_name,
            .declared_at = for_in.item_name,
            .kind = .{ .binding = .{ .binding_mutability = symbols.BindingMutability.immutable } },
        });
        try self.symbol_id_by_node_id.put(node_id, item_symbol_id);
        try loop_scope.insertSymbol(item_name, item_symbol_id);

        var loop_environment = environment;
        loop_environment.node_scope = &loop_scope;
        try self.resolveNode(for_in.body_block, loop_environment);
    }

    fn resolveCallExpressionNode(
        self: *@This(),
        call_expression: ast.CallExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(call_expression.callee, environment);

        for (call_expression.arguments) |*argument| {
            try self.resolveNode(argument, environment);
        }
    }

    fn resolveBinaryExpressionNode(
        self: *@This(),
        binary_expression: ast.BinaryExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(binary_expression.left, environment);
        try self.resolveNode(binary_expression.right, environment);
    }

    fn resolveUnaryExpressionNode(
        self: *@This(),
        unary_expression: ast.UnaryExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(unary_expression.operand, environment);
    }

    fn resolveMemberExpressionNode(
        self: *@This(),
        member_expression: ast.MemberExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(member_expression.base, environment);
    }

    fn resolveIdentifierNode(
        self: *@This(),
        node_id: ast.NodeId,
        identifier: lexing.Token,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        const identifier_name = identifier.kind.identifier;
        const symbol_id = try self.getSymbolIdForName(identifier, identifier_name, environment);
        try self.symbol_id_by_node_id.put(node_id, symbol_id);
    }

    fn resolveBlockNode(
        self: *@This(),
        block: ast.Block,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        var block_scope = scope.Scope.init(self.arena, environment.node_scope);
        var block_environment = environment;
        block_environment.node_scope = &block_scope;
        for (block.statements) |*statement| {
            try self.resolveNode(statement, block_environment);
        }
        if (block.result) |result_node| {
            try self.resolveNode(result_node, block_environment);
        }
    }

    fn resolveIfStatementNode(
        self: *@This(),
        if_statement: ast.IfStatement,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(if_statement.condition, environment);
        try self.resolveNode(if_statement.then_branch, environment);
    }

    fn resolveIfExpressionNode(
        self: *@This(),
        if_expression: ast.IfExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(if_expression.condition, environment);
        try self.resolveNode(if_expression.then_block, environment);
        try self.resolveNode(if_expression.else_block, environment);
    }

    fn resolveMatchExpressionNode(
        self: *@This(),
        match_expression: ast.MatchExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(match_expression.subject, environment);
        for (match_expression.arms) |arm| {
            var body_expression_environment = environment;
            var body_expression_scope = scope.Scope.init(self.arena, environment.node_scope);
            switch (arm.pattern.kind) {
                .case => |case_pattern| {
                    if (case_pattern.qualifier_token) |qualifier_token| {
                        const qualifier_symbol_id = try self.getSymbolIdForName(qualifier_token, qualifier_token.kind.identifier, environment);
                        try self.symbol_id_by_node_id.put(arm.pattern.id, qualifier_symbol_id);
                    }
                    if (case_pattern.binding) |payload_binding| {
                        const binding_name = payload_binding.name_token.kind.identifier;
                        try self.validateBindingDeclarationName(payload_binding.name_token, binding_name, "payload binding", environment);
                        const binding_symbol_id = try self.symbol_table.insertSymbol(.{
                            .name = binding_name,
                            .declared_at = payload_binding.name_token,
                            .kind = .{ .binding = .{ .binding_mutability = symbols.BindingMutability.immutable } },
                        });
                        try self.symbol_id_by_node_id.put(payload_binding.id, binding_symbol_id);
                        try body_expression_scope.insertSymbol(binding_name, binding_symbol_id);

                        body_expression_environment.node_scope = &body_expression_scope;
                    }
                },
                .integer_literal, .boolean_literal, .string_literal => {},
            }

            try self.resolveNode(arm.body_expression, body_expression_environment);
        }
        if (match_expression.else_arm_expression) |else_arm_expression| {
            try self.resolveNode(else_arm_expression, environment);
        }
    }

    fn resolveSubjectlessMatchExpressionNode(
        self: *@This(),
        subjectless_match_expression: ast.SubjectlessMatchExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        for (subjectless_match_expression.arms) |arm| {
            try self.resolveNode(arm.condition, environment);
            try self.resolveNode(arm.body_expression, environment);
        }
        if (subjectless_match_expression.else_arm_expression) |else_arm_expression| {
            try self.resolveNode(else_arm_expression, environment);
        }
    }

    fn resolveExpressionStatementNode(
        self: *@This(),
        expression_statement: ast.ExpressionStatement,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(expression_statement.expression, environment);
    }

    fn resolveStructureLiteralNode(
        self: *@This(),
        structure_literal: ast.StructureLiteral,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        for (structure_literal.fields) |field| {
            try self.resolveNode(field.value, environment);
        }
    }

    fn resolveArrayLiteralNode(
        self: *@This(),
        array_literal: ast.ArrayLiteral,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        for (array_literal.elements) |*element| {
            try self.resolveNode(element, environment);
        }
    }

    fn resolveIndexExpressionNode(
        self: *@This(),
        index_expression: ast.IndexExpression,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        try self.resolveNode(index_expression.base, environment);
        try self.resolveNode(index_expression.index, environment);
    }

    fn getSymbolIdForName(
        self: *@This(),
        identifier_token: lexing.Token,
        name: []const u8,
        environment: ResolutionEnvironment,
    ) CompileError!symbols.SymbolId {
        const symbol_id = environment.node_scope.lookupSymbol(name) orelse environment.module_scope.lookupSymbol(name) orelse {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, identifier_token, "undefined identifier '{s}'", .{name});
            return error.DiagnosticsEmitted;
        };

        return symbol_id;
    }

    fn resolveQualifiedStructureLiteral(
        self: *@This(),
        node_id: ast.NodeId,
        qualified_structure_literal: *const ast.QualifiedStructureLiteral,
        environment: ResolutionEnvironment,
    ) CompileError!void {
        const structure_name = qualified_structure_literal.structure_name.kind.identifier;
        const symbol_id = environment.module_scope.lookupSymbol(structure_name) orelse {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, qualified_structure_literal.structure_name, "undefined structure '{s}'", .{structure_name});
            return error.DiagnosticsEmitted;
        };
        try self.symbol_id_by_node_id.put(node_id, symbol_id);
        for (qualified_structure_literal.fields) |field| {
            try self.resolveNode(field.value, environment);
        }
    }

    fn resolveFunction(
        self: *@This(),
        function_symbol_id: symbols.SymbolId,
        function_definition: *const ast.FunctionDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        var function_scope = scope.Scope.init(self.arena, null);
        var parameter_symbol_ids = std.ArrayList(symbols.SymbolId){};

        for (function_definition.parameters) |*parameter| {
            const parameter_name = parameter.name.kind.identifier;
            try self.validateIdentifierIsAvailable(parameter.name, parameter_name, "parameter");
            function_scope.validateNotInScope(parameter_name) catch {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, parameter.name, "parameter '{s}' is already declared in this function", .{parameter_name});
                return error.DiagnosticsEmitted;
            };

            const parameter_type = try self.resolveTypeExpression(parameter.type_annotation, module_scope);
            const parameter_id = try self.symbol_table.insertSymbol(.{
                .name = parameter_name,
                .declared_at = parameter.name,
                .kind = .{ .binding = .{
                    .binding_mutability = .mutable,
                    .declared_type_reference = parameter_type,
                } },
            });
            try function_scope.insertSymbol(parameter_name, parameter_id);
            try parameter_symbol_ids.append(self.arena, parameter_id);
        }

        const return_type_reference = try self.resolveTypeExpression(function_definition.return_type_annotation, module_scope);
        try self.resolveNode(function_definition.body_expression, .{
            .node_scope = &function_scope,
            .module_scope = module_scope,
            .options = .{
                .module_shadowing = .allowed,
            },
        });

        try self.symbol_table.finalizePreliminarySymbol(function_symbol_id, .{ .function = .{
            .parameter_symbol_ids = try parameter_symbol_ids.toOwnedSlice(self.arena),
            .return_type_reference = return_type_reference,
            .implementation_kind = .user_defined,
        } });
    }

    fn resolveStructureDefinition(
        self: *@This(),
        structure_name: []const u8,
        structure_definition: *const ast.StructureDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        const StructureMemberKind = enum {
            field,
            function,
        };

        const structure_symbol_id = module_scope.lookupSymbol(structure_name) orelse unreachable;

        var resolved_fields = std.ArrayList(symbols.ResolvedStructureField){};
        var member_kind_by_name = std.StringHashMap(StructureMemberKind).init(self.arena);
        for (structure_definition.fields) |field| {
            const field_name = field.name.kind.identifier;
            try self.validateIdentifierIsAvailable(field.name, field_name, "structure member");
            if (member_kind_by_name.get(field_name)) |_| {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, field.name, "structure member '{s}' is already declared in '{s}'", .{ field_name, structure_name });
                return error.DiagnosticsEmitted;
            }
            try member_kind_by_name.put(field_name, .field);

            try resolved_fields.append(self.arena, .{
                .name = field_name,
                .type_reference = try self.resolveTypeExpression(field.type_annotation, module_scope),
            });
        }

        var function_symbol_ids = std.ArrayList(symbols.SymbolId){};
        for (structure_definition.function_definitions) |*node| {
            switch (node.kind) {
                .item_definition => |item_definition| switch (item_definition.definition) {
                    .function => |function_definition| {
                        const function_name = item_definition.identifier_token.kind.identifier;
                        try self.validateIdentifierIsAvailable(item_definition.identifier_token, function_name, "structure member");
                        if (member_kind_by_name.get(function_name)) |_| {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, item_definition.identifier_token, "structure member '{s}' is already declared in '{s}'", .{ function_name, structure_name });
                            return error.DiagnosticsEmitted;
                        }
                        try member_kind_by_name.put(function_name, .function);

                        const method_id = try self.symbol_table.insertPreliminarySymbol(.{
                            .name = function_name,
                            .declared_at = item_definition.item_token,
                            .kind = .function,
                        });
                        try self.symbol_id_by_node_id.put(node.id, method_id);
                        try self.resolveFunction(method_id, &function_definition, module_scope);
                        try function_symbol_ids.append(self.arena, method_id);
                    },
                    else => unreachable,
                },
                else => unreachable,
            }
        }

        try self.symbol_table.finalizePreliminarySymbol(structure_symbol_id, .{ .structure = .{
            .fields = try resolved_fields.toOwnedSlice(self.arena),
            .function_symbol_ids = try function_symbol_ids.toOwnedSlice(self.arena),
        } });
    }

    fn resolveUnionDefinition(
        self: *@This(),
        union_name: []const u8,
        union_definition: *const ast.UnionDefinition,
        module_scope: *scope.ModuleScope,
    ) CompileError!void {
        const UnionMemberKind = enum {
            case,
            function,
        };

        const union_symbol_id = module_scope.lookupSymbol(union_name) orelse unreachable;

        var resolved_cases = std.ArrayList(symbols.ResolvedUnionCase){};
        var member_kind_by_name = std.StringHashMap(UnionMemberKind).init(self.arena);
        for (union_definition.cases) |case| {
            const case_name = case.name.kind.identifier;
            try self.validateIdentifierIsAvailable(case.name, case_name, "union member");
            if (member_kind_by_name.get(case_name)) |_| {
                try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, case.name, "union member '{s}' is already declared in '{s}'", .{ case_name, union_name });
                return error.DiagnosticsEmitted;
            }
            try member_kind_by_name.put(case_name, .case);

            try resolved_cases.append(self.arena, .{
                .name = case_name,
                .type_reference = if (case.type_annotation) |type_annotation|
                    try self.resolveTypeExpression(type_annotation, module_scope)
                else
                    .{ .builtin = .unit },
            });
        }

        var function_symbol_ids = std.ArrayList(symbols.SymbolId){};
        for (union_definition.function_definitions) |*node| {
            switch (node.kind) {
                .item_definition => |item_definition| switch (item_definition.definition) {
                    .function => |function_definition| {
                        const function_name = item_definition.identifier_token.kind.identifier;
                        try self.validateIdentifierIsAvailable(item_definition.identifier_token, function_name, "union member");
                        if (member_kind_by_name.get(function_name)) |_| {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, item_definition.identifier_token, "union member '{s}' is already declared in '{s}'", .{ function_name, union_name });
                            return error.DiagnosticsEmitted;
                        }
                        try member_kind_by_name.put(function_name, .function);

                        const method_id = try self.symbol_table.insertPreliminarySymbol(.{
                            .name = function_name,
                            .declared_at = item_definition.item_token,
                            .kind = .function,
                        });
                        try self.symbol_id_by_node_id.put(node.id, method_id);
                        try self.resolveFunction(method_id, &function_definition, module_scope);
                        try function_symbol_ids.append(self.arena, method_id);
                    },
                    else => unreachable,
                },
                else => unreachable,
            }
        }

        try self.symbol_table.finalizePreliminarySymbol(union_symbol_id, .{ .@"union" = .{
            .cases = try resolved_cases.toOwnedSlice(self.arena),
            .function_symbol_ids = try function_symbol_ids.toOwnedSlice(self.arena),
        } });
    }

    fn resolveTypeExpression(
        self: *@This(),
        type_expression: *const type_expressions.TypeExpression,
        module_scope: *scope.ModuleScope,
    ) CompileError!symbols.ResolvedTypeReference {
        return switch (type_expression.*) {
            .named => |named_type_expression| block: {
                const type_name = named_type_expression.name_token.kind.identifier;
                break :block if (builtinTypeFromName(type_name)) |builtin_type|
                    .{ .builtin = builtin_type }
                else named_type_reference: {
                    const symbol_id = module_scope.lookupSymbol(type_name) orelse {
                        try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, named_type_expression.name_token, "unknown type annotation '{s}'", .{type_name});
                        return error.DiagnosticsEmitted;
                    };
                    switch (self.symbol_table.getSymbolKind(symbol_id)) {
                        .structure, .@"union" => break :named_type_reference symbols.ResolvedTypeReference{ .symbol = symbol_id },
                        else => {
                            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, named_type_expression.name_token, "type annotation '{s}' must refer to a structure or union", .{type_name});
                            return error.DiagnosticsEmitted;
                        },
                    }
                };
            },
            .array => |array_type_expression| block: {
                const array_type_reference = try self.arena.create(symbols.ResolvedTypeReference);
                array_type_reference.* = try self.resolveTypeExpression(array_type_expression.element_type, module_scope);

                break :block .{ .array = array_type_reference };
            },
        };
    }

    fn validateIdentifierIsAvailable(
        self: *@This(),
        identifier_token: lexing.Token,
        identifier_name: []const u8,
        kind_name: []const u8,
    ) CompileError!void {
        if (std.mem.eql(u8, identifier_name, "unit")) {
            try self.diagnostic_store.emitFormattedErrorFromToken(self.arena, identifier_token, "{s} name '{s}' is reserved", .{ kind_name, identifier_name });
            return error.DiagnosticsEmitted;
        }
    }

    fn builtinTypeFromName(name: []const u8) ?symbols.BuiltinType {
        if (std.mem.eql(u8, name, "unit")) return .unit;
        if (std.mem.eql(u8, name, "boolean")) return .boolean;
        if (std.mem.eql(u8, name, "int")) return .integer;
        if (std.mem.eql(u8, name, "string")) return .string;
        return null;
    }
};
