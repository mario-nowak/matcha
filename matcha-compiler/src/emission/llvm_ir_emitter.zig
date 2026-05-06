const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

const Register = []const u8;
const Instruction = []const u8;
const Label = []const u8;
const Storage = []const u8;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);

const llvm_string_type_definition = "%String = type { i8*, i64 }";
const llvm_array_type_definition = "%Array = type { i64, ptr }";
const runtime_print_int_function_name = "matcha_print_int";
const runtime_print_string_function_name = "matcha_print_string";
const runtime_panic_index_out_of_bounds_function_name = "matcha_panic_index_out_of_bounds";

const StringLiteralGlobal = struct {
    name: []const u8,
    content: []const u8,
    len: usize,
};

const LlvmTypeDefinition = struct {
    name: []const u8,
    types: []const u8,
};

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

const LoopContext = struct {
    continue_label: Label,
    leave_label: Label,
};

const LoopConstruct = struct {
    condition: ?*ast.Node,
    update: ?*ast.Node,
    body_block: *ast.Block,
};

const DecisionConstruct = struct {
    subject: ?*const ast.Node,
    arms: []const DecisionArm,
    else_arm: ?*const ast.Node,
    exhaustive_without_else: bool = false,
};

const DecisionArm = struct {
    condition: *const ast.Node,
    body: *const ast.Node,
};

const DecisionLabelNames = struct {
    arm: []const u8,
    else_arm: []const u8,
    next: []const u8,
    continue_label: []const u8,
};

const PhiIncoming = struct {
    label: Label,
    register: Register,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,
    function_return_type_id: typing.TypeId,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
        function_return_type_id: typing.TypeId,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
            .function_return_type_id = function_return_type_id,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.storage_by_symbol_id.deinit();
    }
};

pub const EmissionResult = struct {
    register: ?Register,
    exit_label: ?Label,
};

pub const SymbolGenerator = struct {
    allocator: std.mem.Allocator,
    register_counter: usize,
    storage_counter: usize,
    label_counter: usize,
    string_literal_counter: usize,
    register_prefix: []const u8,
    storage_prefix: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        register_prefix: []const u8,
        storage_prefix: []const u8,
    ) @This() {
        return .{
            .allocator = allocator,
            .register_counter = 0,
            .storage_counter = 0,
            .label_counter = 0,
            .string_literal_counter = 0,
            .register_prefix = register_prefix,
            .storage_prefix = storage_prefix,
        };
    }

    pub fn resetFunctionState(self: *@This()) void {
        self.register_counter = 0;
        self.storage_counter = 0;
        self.label_counter = 0;
    }

    pub fn generateRegister(self: *@This()) Register {
        const register = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ self.register_prefix, self.register_counter },
        ) catch unreachable;
        self.register_counter += 1;

        return register;
    }

    pub fn generateStorage(self: *@This()) Storage {
        const storage = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ self.storage_prefix, self.storage_counter },
        ) catch unreachable;
        self.storage_counter += 1;

        return storage;
    }

    pub fn generateLabel(self: *@This(), label_name: []const u8) Label {
        const label = std.fmt.allocPrint(
            self.allocator,
            "label_{s}_{d}",
            .{ label_name, self.label_counter },
        ) catch unreachable;
        self.label_counter += 1;

        return label;
    }

    pub fn generateStringLiteralGlobalName(self: *@This()) []const u8 {
        const global_name = std.fmt.allocPrint(
            self.allocator,
            "@.string_literal_{d}",
            .{self.string_literal_counter},
        ) catch unreachable;
        self.string_literal_counter += 1;

        return global_name;
    }

    pub fn generateStructureFunctionName(
        self: *@This(),
        structure_symbol: symbols.Symbol,
        function_symbol: symbols.Symbol,
    ) []const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "matcha_structure_{d}_{s}__function_{d}_{s}",
            .{
                structure_symbol.id,
                structure_symbol.name,
                function_symbol.id,
                function_symbol.name,
            },
        ) catch unreachable;
    }

    pub fn generateFunctionName(
        self: *@This(),
        function_symbol: symbols.Symbol,
    ) []const u8 {
        switch (function_symbol.kind) {
            .Function => |function_info| switch (function_info.implementation) {
                .BuiltinPrintInt => return runtime_print_int_function_name,
                .BuiltinPrintString => return runtime_print_string_function_name,
                .UserDefined => {
                    return std.fmt.allocPrint(
                        self.allocator,
                        "matcha_function_{d}_{s}",
                        .{ function_symbol.id, function_symbol.name },
                    ) catch unreachable;
                },
            },
            else => unreachable,
        }
    }

    pub fn generateStructureName(self: *@This(), symbol: symbols.Symbol) []const u8 {
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

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    symbol_generator: SymbolGenerator,
    storage_allocation_instructions: std.ArrayList(Instruction),
    lines: std.ArrayList(Line),
    string_literal_globals: std.ArrayList(StringLiteralGlobal),
    string_literal_global_name_by_node_id: std.AutoHashMap(ast.NodeId, []const u8),
    llvm_matcha_type_by_type_id: std.AutoHashMap(typing.TypeId, LlvmTypeDefinition),
    needs_print_int: bool,
    needs_print_string: bool,
    needs_panic_index_out_of_bounds: bool,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_generator = SymbolGenerator.init(allocator, ".t", ".s"),
            .lines = .{},
            .storage_allocation_instructions = .{},
            .string_literal_globals = .{},
            .string_literal_global_name_by_node_id = std.AutoHashMap(ast.NodeId, []const u8).init(allocator),
            .llvm_matcha_type_by_type_id = std.AutoHashMap(typing.TypeId, LlvmTypeDefinition).init(allocator),
            .needs_print_int = false,
            .needs_print_string = false,
            .needs_panic_index_out_of_bounds = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
        self.storage_allocation_instructions.deinit(self.allocator);
        self.string_literal_globals.deinit(self.allocator);
        self.string_literal_global_name_by_node_id.deinit();
        self.llvm_matcha_type_by_type_id.deinit();
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        self.needs_print_int = false;
        self.needs_print_string = false;
        self.needs_panic_index_out_of_bounds = false;
        self.symbol_generator.string_literal_counter = 0;
        self.string_literal_globals.clearRetainingCapacity();
        self.string_literal_global_name_by_node_id.clearRetainingCapacity();

        var user_defined_functions = std.ArrayList([]const u8){};
        defer user_defined_functions.deinit(self.allocator);
        const user_defined_types = self.emitStructureDefinitions(typed_program);
        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Function => |function_definition| {
                        const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(
                            statement.id,
                        ) orelse unreachable;
                        const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(
                            function_symbol_id,
                        ) orelse unreachable;
                        const function_ir = self.emitFunctionDefinition(
                            statement.id,
                            &function_definition,
                            &resolved_function,
                            null,
                            typed_program,
                        );
                        user_defined_functions.append(self.allocator, function_ir) catch unreachable;
                    },
                    .Structure => {},
                },
                else => {},
            }
        }

        const main_function_ir = self.emitMainFunction(typed_program);

        var sections = std.ArrayList([]const u8){};
        defer sections.deinit(self.allocator);
        sections.append(self.allocator, self.renderModulePreamble()) catch unreachable;
        if (user_defined_types.len > 0) {
            sections.append(self.allocator, user_defined_types) catch unreachable;
        }
        for (user_defined_functions.items) |function_ir| {
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

    fn llvmIrType(type_store: *const typing.TypeStore, type_id: typing.TypeId) []const u8 {
        return switch (type_store.getType(type_id)) {
            .Unit => "void",
            .Boolean => "i1",
            .Integer => "i64",
            .String => "%String",
            .Structure => "ptr",
            .Array => "%Array",
            .Function => |unsupported_type| std.debug.panic(
                "LLVM IR emitter does not support function values, got {any} (type id {d})",
                .{ unsupported_type, type_id },
            ),
            .TaggedUnion => |unsupported_type| std.debug.panic(
                "LLVM IR emitter only supports builtin types for now, got {any} (type id {d})",
                .{ unsupported_type, type_id },
            ),
        };
    }

    fn typeIdFromResolvedTypeReference(
        typed_program: *const typing.TypedProgram,
        type_reference: symbols.ResolvedTypeReference,
    ) typing.TypeId {
        return switch (type_reference) {
            .Builtin => |builtin_type| switch (builtin_type) {
                .Unit => typed_program.type_store.unit_type_id,
                .Boolean => typed_program.type_store.boolean_type_id,
                .Integer => typed_program.type_store.integer_type_id,
                .String => typed_program.type_store.string_type_id,
            },
            .Symbol => |symbol_id| typed_program.type_by_symbol_id.get(symbol_id) orelse unreachable,
            .Array => |element_type_reference| typed_program.type_store.getArrayType(
                typeIdFromResolvedTypeReference(typed_program, element_type_reference.*),
            ) orelse unreachable,
        };
    }

    fn llvmIrTypeFromResolvedTypeReference(
        typed_program: *const typing.TypedProgram,
        type_reference: symbols.ResolvedTypeReference,
    ) []const u8 {
        return llvmIrType(
            &typed_program.type_store,
            typeIdFromResolvedTypeReference(typed_program, type_reference),
        );
    }

    fn renderModulePreamble(self: *@This()) []const u8 {
        var module_preamble_buffer = std.ArrayList(u8){};
        defer module_preamble_buffer.deinit(self.allocator);

        const runtime_symbol_declarations = self.emitRuntimeSymbolDeclarations();
        module_preamble_buffer.writer(self.allocator).print(
            "{s}\n\n{s}\n{s}",
            .{ runtime_symbol_declarations, llvm_string_type_definition, llvm_array_type_definition },
        ) catch unreachable;

        const string_literal_globals_ir = self.renderStringLiteralGlobals();
        if (string_literal_globals_ir.len > 0) {
            module_preamble_buffer.writer(self.allocator).print("\n\n{s}", .{string_literal_globals_ir}) catch unreachable;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{module_preamble_buffer.items}) catch unreachable;
    }

    fn emitRuntimeSymbolDeclarations(self: *const @This()) []const u8 {
        var runtime_symbol_declarations = std.ArrayList(u8){};
        defer runtime_symbol_declarations.deinit(self.allocator);

        runtime_symbol_declarations.writer(self.allocator).print(
            \\declare void @matcha_initiate_garbage_collector()
            \\declare ptr @matcha_allocate(i64)
            \\declare ptr @matcha_allocate_atomic(i64)
        ,
            .{},
        ) catch unreachable;

        if (self.needs_print_int) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(i64)",
                .{runtime_print_int_function_name},
            ) catch unreachable;
        }
        if (self.needs_print_string) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(ptr, i64)",
                .{runtime_print_string_function_name},
            ) catch unreachable;
        }
        if (self.needs_panic_index_out_of_bounds) {
            runtime_symbol_declarations.writer(self.allocator).print(
                "\ndeclare void @{s}(i64, i64, i64, i64) noreturn",
                .{runtime_panic_index_out_of_bounds_function_name},
            ) catch unreachable;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{runtime_symbol_declarations.items}) catch unreachable;
    }

    fn renderStringLiteralGlobals(self: *@This()) []const u8 {
        var globals_buffer = std.ArrayList(u8){};
        defer globals_buffer.deinit(self.allocator);

        for (self.string_literal_globals.items, 0..) |string_literal_global, index| {
            const rendered_content = self.renderLlvmStringLiteralContent(string_literal_global.content);
            globals_buffer.writer(self.allocator).print(
                "{s} = private unnamed_addr constant [{d} x i8] c\"{s}\"",
                .{ string_literal_global.name, string_literal_global.len, rendered_content },
            ) catch unreachable;
            if (index + 1 < self.string_literal_globals.items.len) {
                globals_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{globals_buffer.items}) catch unreachable;
    }

    fn renderLlvmStringLiteralContent(self: *@This(), content: []const u8) []const u8 {
        var rendered_content_buffer = std.ArrayList(u8){};
        defer rendered_content_buffer.deinit(self.allocator);

        // LLVM c"..." literals encode raw bytes, so quotes, backslashes, and
        // non-printable bytes must be emitted as \XX escapes to preserve content.
        for (content) |byte| {
            if (byte >= 0x20 and byte <= 0x7e and byte != '\\' and byte != '"') {
                rendered_content_buffer.append(self.allocator, byte) catch unreachable;
                continue;
            }

            rendered_content_buffer.writer(self.allocator).print("\\{X:0>2}", .{byte}) catch unreachable;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{rendered_content_buffer.items}) catch unreachable;
    }

    fn ensureStringLiteralGlobalName(self: *@This(), node_id: ast.NodeId, content: []const u8) []const u8 {
        if (self.string_literal_global_name_by_node_id.get(node_id)) |existing_global_name| {
            return existing_global_name;
        }

        const global_name = self.symbol_generator.generateStringLiteralGlobalName();
        self.string_literal_globals.append(self.allocator, .{
            .name = global_name,
            .content = content,
            .len = content.len,
        }) catch unreachable;
        self.string_literal_global_name_by_node_id.put(node_id, global_name) catch unreachable;

        return global_name;
    }

    fn emitStringLiteralPointer(self: *@This(), global_name: []const u8, len: usize) Register {
        const pointer_register = self.symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [{d} x i8], [{d} x i8]* {s}, i64 0, i64 0",
            .{ pointer_register, len, len, global_name },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = pointer_instruction }) catch unreachable;

        return pointer_register;
    }

    fn emitStringValue(self: *@This(), pointer_register: Register, len: usize) Register {
        const partial_string_register = self.symbol_generator.generateRegister();
        const partial_string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String undef, i8* {s}, 0",
            .{ partial_string_register, pointer_register },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = partial_string_instruction }) catch unreachable;

        const string_register = self.symbol_generator.generateRegister();
        const string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String {s}, i64 {d}, 1",
            .{ string_register, partial_string_register, len },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = string_instruction }) catch unreachable;

        return string_register;
    }

    fn emitStringLiteral(self: *@This(), node: *const ast.Node, content: []const u8, entry_label: Label) EmissionResult {
        const global_name = self.ensureStringLiteralGlobalName(node.id, content);
        const pointer_register = self.emitStringLiteralPointer(global_name, content.len);
        const string_register = self.emitStringValue(pointer_register, content.len);

        return .{
            .exit_label = entry_label,
            .register = string_register,
        };
    }

    fn resetCurrentFunctionState(self: *@This()) void {
        self.lines.deinit(self.allocator);
        self.storage_allocation_instructions.deinit(self.allocator);
        self.symbol_generator.resetFunctionState();
        self.lines = .{};
        self.storage_allocation_instructions = .{};
    }

    fn renderCurrentFunction(
        self: *@This(),
        function_name: []const u8,
        return_llvm_ir_type: []const u8,
        parameter_list: []const u8,
    ) []const u8 {
        var storage_allocation_buffer = std.ArrayList(u8){};
        defer storage_allocation_buffer.deinit(self.allocator);
        for (self.storage_allocation_instructions.items) |instruction| {
            storage_allocation_buffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
        }

        var instructions_buffer = std.ArrayList(u8){};
        defer instructions_buffer.deinit(self.allocator);
        for (self.lines.items) |line| {
            switch (line) {
                .instruction => |instruction| {
                    instructions_buffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
                },
                .label => |label| {
                    instructions_buffer.writer(self.allocator).print("{s}:\n", .{label}) catch unreachable;
                },
            }
        }

        return std.fmt.allocPrint(
            self.allocator,
            \\define {s} @{s}({s}) {{
            \\entry:
            \\{s}
            \\{s}
            \\}}
        ,
            .{
                return_llvm_ir_type,
                function_name,
                parameter_list,
                storage_allocation_buffer.items,
                instructions_buffer.items,
            },
        ) catch unreachable;
    }

    fn emitMainFunction(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        self.resetCurrentFunctionState();

        var environment = Environment.init(self.allocator, null, typed_program.type_store.integer_type_id);
        defer environment.deinit();
        var current_label: Label = "entry";

        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .ItemDefinition => continue,
                else => {},
            }

            const result = self.emitNode(statement, current_label, typed_program, &environment);
            if (result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                break;
            }
        }

        self.lines.append(self.allocator, .{ .instruction = "ret i32 0" }) catch unreachable;

        return self.renderCurrentFunction("main", "i32", "");
    }

    fn emitFunctionDefinition(
        self: *@This(),
        function_node_id: ast.NodeId,
        function_definition: *const ast.Function,
        resolved_function: *const symbols.ResolvedFunction,
        owning_structure_symbol: ?symbols.Symbol,
        typed_program: *const typing.TypedProgram,
    ) []const u8 {
        self.resetCurrentFunctionState();

        const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(function_node_id) orelse unreachable;
        const function_symbol = typed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_type_id = typed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_type_id = switch (typed_program.type_store.getType(function_type_id)) {
            .Function => |id| typed_program.type_store.function_types.items[id].return_type,
            else => unreachable,
        };
        const function_return_llvm_ir_type = llvmIrType(&typed_program.type_store, function_return_type_id);

        var parameter_list_buffer = std.ArrayList(u8){};
        defer parameter_list_buffer.deinit(self.allocator);
        var environment = Environment.init(self.allocator, null, function_return_type_id);
        defer environment.deinit();

        for (resolved_function.parameters, 0..) |parameter, index| {
            const parameter_type_id = typed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = llvmIrType(&typed_program.type_store, parameter_type_id);
            const parameter_register = std.fmt.allocPrint(
                self.allocator,
                "%arg_{d}_{s}",
                .{ index, parameter.name },
            ) catch unreachable;

            if (index > 0) {
                parameter_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            parameter_list_buffer.writer(self.allocator).print(
                "{s} {s}",
                .{ parameter_llvm_ir_type, parameter_register },
            ) catch unreachable;

            const storage = self.symbol_generator.generateStorage();
            self.emitAlloca(storage, parameter_llvm_ir_type);
            self.emitStore(parameter_register, storage, parameter_llvm_ir_type);
            environment.storage_by_symbol_id.put(parameter.symbol_id, storage) catch unreachable;
        }

        const body_result = self.emitNode(
            function_definition.body_expression,
            "entry",
            typed_program,
            &environment,
        );

        if (body_result.exit_label != null) {
            switch (typed_program.type_store.getType(function_return_type_id)) {
                .Unit => {
                    self.lines.append(self.allocator, .{ .instruction = "ret void" }) catch unreachable;
                },
                else => {
                    const return_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "ret {s} {s}",
                        .{ function_return_llvm_ir_type, body_result.register orelse unreachable },
                    ) catch unreachable;
                    self.lines.append(self.allocator, .{ .instruction = return_instruction }) catch unreachable;
                },
            }
        }

        return self.renderCurrentFunction(
            if (owning_structure_symbol) |structure_symbol|
                self.symbol_generator.generateStructureFunctionName(structure_symbol, function_symbol)
            else
                self.symbol_generator.generateFunctionName(function_symbol),
            function_return_llvm_ir_type,
            parameter_list_buffer.items,
        );
    }

    fn emitRuntimePrintStringCall(self: *@This(), string_register: Register) void {
        const pointer_register = self.symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 0",
            .{ pointer_register, string_register },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = pointer_instruction }) catch unreachable;

        const length_register = self.symbol_generator.generateRegister();
        const length_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String {s}, 1",
            .{ length_register, string_register },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = length_instruction }) catch unreachable;

        const print_instruction = std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(ptr {s}, i64 {s})",
            .{ runtime_print_string_function_name, pointer_register, length_register },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = print_instruction }) catch unreachable;
    }

    fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        switch (node.kind) {
            .Return => |return_statement| {
                if (return_statement.value) |return_value| {
                    const value_result = self.emitNode(
                        return_value,
                        entry_label,
                        typed_program,
                        environment,
                    );
                    if (value_result.exit_label == null) {
                        return .{
                            .exit_label = null,
                            .register = null,
                        };
                    }

                    const return_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "ret {s} {s}",
                        .{
                            llvmIrType(&typed_program.type_store, environment.function_return_type_id),
                            value_result.register.?,
                        },
                    ) catch unreachable;
                    self.lines.append(self.allocator, .{ .instruction = return_instruction }) catch unreachable;
                } else {
                    self.lines.append(self.allocator, .{ .instruction = "ret void" }) catch unreachable;
                }

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .IntegerLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = std.fmt.allocPrint(
                        self.allocator,
                        "{d}",
                        .{token.kind.IntLiteral},
                    ) catch unreachable,
                };
            },
            .BooleanLiteral => |token| {
                return .{
                    .exit_label = entry_label,
                    .register = if (token.kind.BooleanLiteral) "1" else "0",
                };
            },
            .StringLiteral => |token| return self.emitStringLiteral(node, token.kind.StringLiteral, entry_label),
            .Identifier => {
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const llvm_ir_type = llvmIrType(
                    &typed_program.type_store,
                    typed_program.type_by_node_id.get(node.id).?,
                );
                const register = self.symbol_generator.generateRegister();
                self.emitLoad(register, storage, llvm_ir_type);

                return .{
                    .exit_label = entry_label,
                    .register = register,
                };
            },
            .Loop => |loop| {
                var body_block = switch (loop.body_block.kind) {
                    .Block => |block| block,
                    else => unreachable,
                };

                const loop_construct = LoopConstruct{
                    .condition = null,
                    .body_block = &body_block,
                    .update = null,
                };

                return self.emitLoopConstruct(
                    loop_construct,
                    typed_program,
                    environment,
                );
            },
            .While => |while_statement| {
                var body_block = switch (while_statement.body_block.kind) {
                    .Block => |block| block,
                    else => unreachable,
                };

                const loop_construct = LoopConstruct{
                    .condition = while_statement.condition,
                    .body_block = &body_block,
                    .update = while_statement.update,
                };

                return self.emitLoopConstruct(
                    loop_construct,
                    typed_program,
                    environment,
                );
            },
            .Leave => {
                self.emitBranchInstruction(null, &.{environment.loop_context.?.leave_label});

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .Continue => {
                self.emitBranchInstruction(null, &.{environment.loop_context.?.continue_label});

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .CallExpression => |call_expression| {
                const structure_function_access = switch (call_expression.callee.kind) {
                    .MemberAccess => structure_function_access_from_member_access: {
                        const member_access = typed_program.member_access_by_node_id.get(call_expression.callee.id) orelse unreachable;
                        break :structure_function_access_from_member_access switch (member_access) {
                            .StructureTypeFunctionAccess => |structure_function| structure_function,
                            else => null,
                        };
                    },
                    else => null,
                };
                const callee_symbol_id = if (structure_function_access) |structure_function|
                    structure_function.function_symbol_id
                else
                    typed_program.resolved_program.symbol_id_by_node_id.get(
                        call_expression.callee.id,
                    ) orelse unreachable;
                const callee_symbol = typed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
                const function_info = switch (callee_symbol.kind) {
                    .Function => |function_info| function_info,
                    else => unreachable,
                };

                const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                var current_label = entry_label;
                var argument_registers = std.ArrayList(Register){};
                defer argument_registers.deinit(self.allocator);
                for (call_expression.arguments) |*argument| {
                    const argument_result = self.emitNode(
                        argument,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (argument_result.exit_label) |exit_label| {
                        current_label = exit_label;
                    } else {
                        return .{
                            .exit_label = null,
                            .register = null,
                        };
                    }
                    argument_registers.append(
                        self.allocator,
                        argument_result.register orelse unreachable,
                    ) catch unreachable;
                }

                switch (function_info.implementation) {
                    .BuiltinPrintInt => self.needs_print_int = true,
                    .BuiltinPrintString => {
                        self.needs_print_string = true;
                        self.emitRuntimePrintStringCall(argument_registers.items[0]);

                        return .{
                            .exit_label = current_label,
                            .register = null,
                        };
                    },
                    .UserDefined => {},
                }

                var argument_list_buffer = std.ArrayList(u8){};
                defer argument_list_buffer.deinit(self.allocator);
                for (resolved_function.parameters, argument_registers.items, 0..) |parameter, argument_register, index| {
                    const parameter_type_id = typed_program.type_by_symbol_id.get(parameter.symbol_id) orelse unreachable;
                    if (index > 0) {
                        argument_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
                    }
                    argument_list_buffer.writer(self.allocator).print(
                        "{s} {s}",
                        .{
                            llvmIrType(&typed_program.type_store, parameter_type_id),
                            argument_register,
                        },
                    ) catch unreachable;
                }

                const function_name = if (structure_function_access) |structure_function|
                    self.symbol_generator.generateStructureFunctionName(
                        typed_program.resolved_program.symbol_table.getSymbol(structure_function.structure_symbol_id),
                        callee_symbol,
                    )
                else
                    self.symbol_generator.generateFunctionName(callee_symbol);
                const function_type_id = typed_program.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                const function_return_type_id = switch (typed_program.type_store.getType(function_type_id)) {
                    .Function => |id| typed_program.type_store.function_types.items[id].return_type,
                    else => unreachable,
                };
                const function_return_llvm_ir_type = llvmIrType(&typed_program.type_store, function_return_type_id);
                if (function_return_type_id == typed_program.type_store.unit_type_id) {
                    const call_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "call {s} @{s}({s})",
                        .{ function_return_llvm_ir_type, function_name, argument_list_buffer.items },
                    ) catch unreachable;
                    self.lines.append(self.allocator, .{ .instruction = call_instruction }) catch unreachable;

                    return .{
                        .exit_label = current_label,
                        .register = null,
                    };
                }

                const result_register = self.symbol_generator.generateRegister();
                const call_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = call {s} @{s}({s})",
                    .{ result_register, function_return_llvm_ir_type, function_name, argument_list_buffer.items },
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = call_instruction }) catch unreachable;

                return .{
                    .exit_label = current_label,
                    .register = result_register,
                };
            },
            .MemberAccess => |member_access| return self.emitMemberAccess(
                node,
                &member_access,
                entry_label,
                typed_program,
                environment,
            ),
            .BinaryExpression => |binary_expression| {
                const left_result = self.emitNode(
                    binary_expression.left,
                    entry_label,
                    typed_program,
                    environment,
                );
                const right_result = self.emitNode(
                    binary_expression.right,
                    left_result.exit_label.?,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generateRegister();
                const operator = switch (binary_expression.operator) {
                    .Add => "add",
                    .Subtract => "sub",
                    .Multiply => "mul",
                    .Divide => "sdiv",
                    .Equal => "icmp eq",
                    .NotEqual => "icmp ne",
                    .LessThan => "icmp slt",
                    .LessThanOrEqual => "icmp sle",
                    .GreaterThan => "icmp sgt",
                    .GreaterThanOrEqual => "icmp sge",
                    .And => "and",
                    .Or => "or",
                };
                const left_operand_type = typed_program.type_by_node_id.get(binary_expression.left.id).?;
                const instruction_type = llvmIrType(&typed_program.type_store, left_operand_type);
                const instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = {s} {s} {s}, {s}",
                    .{ result_register, operator, instruction_type, left_result.register.?, right_result.register.? },
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;

                return .{
                    .exit_label = right_result.exit_label,
                    .register = result_register,
                };
            },
            .UnaryExpression => |unary_expression| {
                const operand_result = self.emitNode(
                    unary_expression.operand,
                    entry_label,
                    typed_program,
                    environment,
                );
                const result_register = self.symbol_generator.generateRegister();
                const operation_type = typed_program.type_by_node_id.get(node.id).?;
                const instruction_type = llvmIrType(&typed_program.type_store, operation_type);
                const instruction = switch (unary_expression.operator) {
                    .Negate => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = sub {s} 0, {s}",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                    .Not => std.fmt.allocPrint(
                        self.allocator,
                        "{s} = xor {s} {s}, 1",
                        .{ result_register, instruction_type, operand_result.register.? },
                    ) catch unreachable,
                };
                self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;

                return .{
                    .exit_label = operand_result.exit_label,
                    .register = result_register,
                };
            },
            .Declaration => |value_declaration| {
                const value_declaration_result = self.emitNode(
                    value_declaration.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const value_type_id = typed_program.type_by_node_id.get(value_declaration.value.id).?;
                const llvm_ir_type = llvmIrType(&typed_program.type_store, value_type_id);

                const storage = self.symbol_generator.generateStorage();
                self.emitAlloca(storage, llvm_ir_type);
                self.emitStore(value_declaration_result.register.?, storage, llvm_ir_type);

                environment.storage_by_symbol_id.put(symbol_id, storage) catch unreachable;

                return .{
                    .exit_label = value_declaration_result.exit_label,
                    .register = null,
                };
            },
            .Assignment => |assignment| {
                const place_result = self.emitPlace(
                    assignment.target,
                    entry_label,
                    typed_program,
                    environment,
                );
                if (place_result.exit_label == null) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                const value_result = self.emitNode(
                    assignment.value,
                    place_result.exit_label.?,
                    typed_program,
                    environment,
                );
                const value_type_id = typed_program.type_by_node_id.get(assignment.target.id).?;
                const llvm_ir_type = llvmIrType(&typed_program.type_store, value_type_id);
                self.emitStore(value_result.register.?, place_result.register.?, llvm_ir_type);

                return .{
                    .exit_label = value_result.exit_label,
                    .register = null,
                };
            },
            .Block => |block| return self.emitBlock(
                block,
                entry_label,
                typed_program,
                environment,
            ),
            .IfStatement => |if_statement| {
                const decision_arms = [_]DecisionArm{.{
                    .condition = if_statement.condition,
                    .body = if_statement.then_branch,
                }};
                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = null,
                        .arms = &decision_arms,
                        .else_arm = null,
                    },
                    .{
                        .arm = "then",
                        .else_arm = "else",
                        .next = "next",
                        .continue_label = "continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .IfExpression => |if_expression| {
                const decision_arms = [_]DecisionArm{.{
                    .condition = if_expression.condition,
                    .body = if_expression.then_block,
                }};
                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = null,
                        .arms = &decision_arms,
                        .else_arm = if_expression.else_block,
                    },
                    .{
                        .arm = "then",
                        .else_arm = "else",
                        .next = "next",
                        .continue_label = "continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .MatchExpression => |match_expression| {
                var decision_arms = std.ArrayList(DecisionArm){};
                defer decision_arms.deinit(self.allocator);
                for (match_expression.arms) |arm| {
                    decision_arms.append(self.allocator, .{
                        .condition = arm.pattern_or_condition,
                        .body = arm.body,
                    }) catch unreachable;
                }

                const exhaustive_without_else = if (match_expression.subject) |subject|
                    match_expression.else_arm == null and
                        typed_program.type_by_node_id.get(subject.id).? == typed_program.type_store.boolean_type_id
                else
                    false;

                return self.emitDecisionConstruct(
                    node,
                    .{
                        .subject = match_expression.subject,
                        .arms = decision_arms.items,
                        .else_arm = match_expression.else_arm,
                        .exhaustive_without_else = exhaustive_without_else,
                    },
                    .{
                        .arm = "match_arm",
                        .else_arm = "match_else",
                        .next = "match_next",
                        .continue_label = "match_continue",
                    },
                    entry_label,
                    typed_program,
                    environment,
                );
            },
            .ExpressionStatement => |expression_statement| {
                const emission_result = self.emitNode(
                    expression_statement.expression,
                    entry_label,
                    typed_program,
                    environment,
                );

                return .{
                    .exit_label = emission_result.exit_label,
                    .register = null,
                };
            },
            .ItemDefinition => {
                return .{
                    .exit_label = entry_label,
                    .register = null,
                };
            },
            .StructureConstruction => |structure_construction| return self.emitStructureConstruction(
                node,
                &structure_construction,
                entry_label,
                typed_program,
                environment,
            ),
            .ArrayLiteral => |array_literal| return self.emitArrayLiteral(
                node,
                &array_literal,
                entry_label,
                typed_program,
                environment,
            ),
            .IndexAccess => |index_access| return self.emitIndexAccess(
                node,
                &index_access,
                entry_label,
                typed_program,
                environment,
            ),
        }
    }

    fn emitMemberAccess(
        self: *@This(),
        node: *const ast.Node,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const resolved_member_access = typed_program.member_access_by_node_id.get(node.id) orelse unreachable;
        switch (resolved_member_access) {
            .ArrayInstanceLengthAccess => {
                const base_result = self.emitNode(
                    member_access.base,
                    entry_label,
                    typed_program,
                    environment,
                );
                if (base_result.exit_label == null) {
                    return .{ .exit_label = null, .register = null };
                }

                const length_register = self.symbol_generator.generateRegister();
                self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
                    self.allocator,
                    "{s} = extractvalue %Array {s}, 0",
                    .{ length_register, base_result.register orelse unreachable },
                ) catch unreachable }) catch unreachable;

                return .{
                    .exit_label = base_result.exit_label,
                    .register = length_register,
                };
            },
            .StructureInstanceFieldAccess => {
                const member_pointer_result = self.emitMemberAccessPointer(
                    node.id,
                    member_access,
                    entry_label,
                    typed_program,
                    environment,
                );
                if (member_pointer_result.exit_label == null) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                const member_register = self.symbol_generator.generateRegister();
                self.emitLoad(
                    member_register,
                    member_pointer_result.register.?,
                    llvmIrType(&typed_program.type_store, typed_program.type_by_node_id.get(node.id).?),
                );

                return .{
                    .exit_label = member_pointer_result.exit_label,
                    .register = member_register,
                };
            },
            .StructureTypeFunctionAccess => unreachable,
        }
    }

    fn emitPlace(
        self: *@This(),
        target: *const ast.Node,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        switch (target.kind) {
            .Identifier => {
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(target.id).?;
                return .{
                    .exit_label = entry_label,
                    .register = environment.storage_by_symbol_id.get(symbol_id).?,
                };
            },
            .MemberAccess => |member_access| return self.emitMemberAccessPointer(
                target.id,
                &member_access,
                entry_label,
                typed_program,
                environment,
            ),
            .IndexAccess => |index_access| return self.emitIndexAccessPointer(
                &index_access,
                entry_label,
                typed_program,
                environment,
            ),
            else => unreachable,
        }
    }

    fn emitMemberAccessPointer(
        self: *@This(),
        node_id: ast.NodeId,
        member_access: *const ast.MemberAccess,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(
            member_access.base,
            entry_label,
            typed_program,
            environment,
        );
        if (base_result.exit_label == null) {
            return .{
                .exit_label = null,
                .register = null,
            };
        }

        const resolved_member_access = typed_program.member_access_by_node_id.get(node_id) orelse unreachable;
        const field_index = switch (resolved_member_access) {
            .StructureInstanceFieldAccess => |structure_field| structure_field.field_index,
            .ArrayInstanceLengthAccess => unreachable,
            .StructureTypeFunctionAccess => unreachable,
        };

        const base_type_id = typed_program.type_by_node_id.get(member_access.base.id) orelse unreachable;
        switch (typed_program.type_store.getType(base_type_id)) {
            .Structure => {},
            else => unreachable,
        }
        const structure_symbol = self.getStructureSymbolForTypeId(typed_program, base_type_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);

        const field_pointer_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ field_pointer_register, structure_llvm_type_name, base_result.register orelse unreachable, field_index },
        ) catch unreachable }) catch unreachable;

        return .{
            .exit_label = base_result.exit_label,
            .register = field_pointer_register,
        };
    }

    fn emitStructureConstruction(
        self: *@This(),
        node: *const ast.Node,
        structure_construction: *const ast.StructureConstruction,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const structure_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id) orelse unreachable;
        const structure_symbol = typed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);
        const structure_type_id = switch (typed_program.type_store.getType(typed_program.type_by_symbol_id.get(structure_symbol_id) orelse unreachable)) {
            .Structure => |id| id,
            else => unreachable,
        };
        const structure_type = typed_program.type_store.structure_types.items[structure_type_id];
        const structure_construction_layout = typed_program.structure_construction_layout_by_node_id.get(
            node.id,
        ) orelse unreachable;

        const memory_register = self.symbol_generator.generateRegister();
        self.lines.append(
            self.allocator,
            .{ .instruction = std.fmt.allocPrint(
                self.allocator,
                "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr (%{s}, ptr null, i32 1) to i64))",
                .{ memory_register, structure_llvm_type_name },
            ) catch unreachable },
        ) catch unreachable;

        var current_label: Label = entry_label;
        for (structure_construction.fields, structure_construction_layout.field_indices) |field, field_index| {
            const structure_field = structure_type.fields[@intCast(field_index)];
            const field_value_result = self.emitNode(
                field.value,
                current_label,
                typed_program,
                environment,
            );
            if (field_value_result.exit_label == null) {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
            current_label = field_value_result.exit_label.?;

            const field_pointer_register = self.symbol_generator.generateRegister();
            self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
                self.allocator,
                "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
                .{ field_pointer_register, structure_llvm_type_name, memory_register, field_index },
            ) catch unreachable }) catch unreachable;

            const field_llvm_ir_type = llvmIrType(&typed_program.type_store, structure_field.type_id);
            self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
                self.allocator,
                "store {s} {s}, ptr {s}",
                .{ field_llvm_ir_type, field_value_result.register orelse unreachable, field_pointer_register },
            ) catch unreachable }) catch unreachable;
        }

        return .{
            .exit_label = current_label,
            .register = memory_register,
        };
    }

    fn emitArrayLiteral(
        self: *@This(),
        node: *const ast.Node,
        array_literal: *const ast.ArrayLiteral,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const array_type_id = typed_program.type_by_node_id.get(node.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(array_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);
        const length = array_literal.elements.len;

        const data_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = call ptr @matcha_allocate(i64 ptrtoint (ptr getelementptr ({s}, ptr null, i64 {d}) to i64))",
            .{ data_register, element_llvm_type, length },
        ) catch unreachable }) catch unreachable;

        var current_label: Label = entry_label;
        for (array_literal.elements, 0..) |*element, index| {
            const element_result = self.emitNode(element, current_label, typed_program, environment);
            if (element_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }
            current_label = element_result.exit_label.?;

            const element_pointer_register = self.symbol_generator.generateRegister();
            self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
                self.allocator,
                "{s} = getelementptr inbounds {s}, ptr {s}, i64 {d}",
                .{ element_pointer_register, element_llvm_type, data_register, index },
            ) catch unreachable }) catch unreachable;

            self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
                self.allocator,
                "store {s} {s}, ptr {s}",
                .{ element_llvm_type, element_result.register orelse unreachable, element_pointer_register },
            ) catch unreachable }) catch unreachable;
        }

        const partial_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %Array undef, i64 {d}, 0",
            .{ partial_register, length },
        ) catch unreachable }) catch unreachable;

        const array_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %Array {s}, ptr {s}, 1",
            .{ array_register, partial_register, data_register },
        ) catch unreachable }) catch unreachable;

        return .{
            .exit_label = current_label,
            .register = array_register,
        };
    }

    fn emitIndexAccess(
        self: *@This(),
        node: *const ast.Node,
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        _ = node;
        const pointer_result = self.emitIndexAccessPointer(
            index_access,
            entry_label,
            typed_program,
            environment,
        );
        if (pointer_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const base_type_id = typed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        const result_register = self.symbol_generator.generateRegister();
        self.emitLoad(result_register, pointer_result.register orelse unreachable, element_llvm_type);

        return .{
            .exit_label = pointer_result.exit_label,
            .register = result_register,
        };
    }

    fn emitIndexAccessPointer(
        self: *@This(),
        index_access: *const ast.IndexAccess,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const base_result = self.emitNode(index_access.base, entry_label, typed_program, environment);
        if (base_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const index_result = self.emitNode(index_access.index, base_result.exit_label.?, typed_program, environment);
        if (index_result.exit_label == null) {
            return .{ .exit_label = null, .register = null };
        }

        const base_type_id = typed_program.type_by_node_id.get(index_access.base.id) orelse unreachable;
        const element_type_id = switch (typed_program.type_store.getType(base_type_id)) {
            .Array => |id| id,
            else => unreachable,
        };
        const element_llvm_type = llvmIrType(&typed_program.type_store, element_type_id);

        const length_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %Array {s}, 0",
            .{ length_register, base_result.register orelse unreachable },
        ) catch unreachable }) catch unreachable;

        const data_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %Array {s}, 1",
            .{ data_register, base_result.register orelse unreachable },
        ) catch unreachable }) catch unreachable;

        const negative_check_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = icmp slt i64 {s}, 0",
            .{ negative_check_register, index_result.register orelse unreachable },
        ) catch unreachable }) catch unreachable;

        const overflow_check_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = icmp sge i64 {s}, {s}",
            .{ overflow_check_register, index_result.register orelse unreachable, length_register },
        ) catch unreachable }) catch unreachable;

        const out_of_bounds_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = or i1 {s}, {s}",
            .{ out_of_bounds_register, negative_check_register, overflow_check_register },
        ) catch unreachable }) catch unreachable;

        const panic_label = self.symbol_generator.generateLabel("index_panic");
        const ok_label = self.symbol_generator.generateLabel("index_ok");
        self.emitBranchInstruction(out_of_bounds_register, &.{ panic_label, ok_label });

        self.emitLabel(panic_label);
        self.needs_panic_index_out_of_bounds = true;
        const line = index_access.left_bracket.line;
        const column = index_access.left_bracket.column;
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "call void @{s}(i64 {d}, i64 {d}, i64 {s}, i64 {s})",
            .{
                runtime_panic_index_out_of_bounds_function_name,
                line,
                column,
                index_result.register orelse unreachable,
                length_register,
            },
        ) catch unreachable }) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = "unreachable" }) catch unreachable;

        self.emitLabel(ok_label);
        const element_pointer_register = self.symbol_generator.generateRegister();
        self.lines.append(self.allocator, .{ .instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
            .{ element_pointer_register, element_llvm_type, data_register, index_result.register orelse unreachable },
        ) catch unreachable }) catch unreachable;

        return .{
            .exit_label = ok_label,
            .register = element_pointer_register,
        };
    }

    fn getStructureSymbolForTypeId(
        self: *@This(),
        typed_program: *const typing.TypedProgram,
        type_id: typing.TypeId,
    ) symbols.Symbol {
        _ = self;

        var iterator = typed_program.type_by_symbol_id.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.* != type_id) {
                continue;
            }

            const symbol = typed_program.resolved_program.symbol_table.getSymbol(entry.key_ptr.*);
            switch (symbol.kind) {
                .Structure => return symbol,
                else => continue,
            }
        }

        unreachable;
    }

    fn emitStructureDefinitions(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        var structure_definitions_buffer = std.ArrayList(u8){};
        defer structure_definitions_buffer.deinit(self.allocator);

        var has_structure_definition = false;
        for (typed_program.resolved_program.program.statements) |*statement| {
            const structure_definition = switch (statement.kind) {
                .ItemDefinition => |item_definition| switch (item_definition.item) {
                    .Structure => |structure| structure,
                    else => continue,
                },
                else => continue,
            };

            const structure_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(statement.id) orelse unreachable;
            const structure_symbol = typed_program.resolved_program.symbol_table.getSymbol(structure_symbol_id);
            const resolved_structure = typed_program.resolved_program.resolved_structure_by_symbol_id.get(structure_symbol_id) orelse unreachable;

            if (has_structure_definition) {
                structure_definitions_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
            structure_definitions_buffer.writer(self.allocator).print(
                "{s}",
                .{self.emitStructureDefinition(resolved_structure, typed_program)},
            ) catch unreachable;
            has_structure_definition = true;

            for (structure_definition.function_definitions) |function_definition_node| {
                const function_definition = switch (function_definition_node.kind) {
                    .ItemDefinition => |item_definition| switch (item_definition.item) {
                        .Function => |function| function,
                        else => unreachable,
                    },
                    else => unreachable,
                };
                const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(
                    function_definition_node.id,
                ) orelse unreachable;
                const resolved_function = typed_program.resolved_program.resolved_function_by_symbol_id.get(function_symbol_id) orelse unreachable;
                const function_definition_emission = self.emitFunctionDefinition(
                    function_definition_node.id,
                    &function_definition,
                    &resolved_function,
                    structure_symbol,
                    typed_program,
                );
                structure_definitions_buffer.writer(self.allocator).print("\n{s}", .{function_definition_emission}) catch unreachable;
            }
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{structure_definitions_buffer.items}) catch unreachable;
    }

    fn emitStructureDefinition(
        self: *@This(),
        resolved_structure: symbols.ResolvedStructure,
        typed_program: *const typing.TypedProgram,
    ) []const u8 {
        const structure_symbol = typed_program.resolved_program.symbol_table.getSymbol(resolved_structure.symbol_id);
        const structure_llvm_type_name = self.symbol_generator.generateStructureName(structure_symbol);

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
            structure_definition_buffer.writer(self.allocator).print(
                "{s}",
                .{llvmIrTypeFromResolvedTypeReference(typed_program, field.type_reference)},
            ) catch unreachable;
        }
        if (resolved_structure.fields.len > 0) {
            structure_definition_buffer.writer(self.allocator).print(" ", .{}) catch unreachable;
        }
        structure_definition_buffer.writer(self.allocator).print("}}", .{}) catch unreachable;

        return std.fmt.allocPrint(self.allocator, "{s}", .{structure_definition_buffer.items}) catch unreachable;
    }

    fn emitDecisionConstruct(
        self: *@This(),
        node: *const ast.Node,
        decision_construct: DecisionConstruct,
        label_names: DecisionLabelNames,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        var current_label = entry_label;
        var subject_register: ?Register = null;
        var subject_type_id: ?typing.TypeId = null;

        if (decision_construct.subject) |subject| {
            const subject_result = self.emitNode(subject, current_label, typed_program, environment);
            if (subject_result.exit_label == null) {
                return .{ .exit_label = null, .register = null };
            }
            current_label = subject_result.exit_label.?;
            subject_register = subject_result.register;
            subject_type_id = typed_program.type_by_node_id.get(subject.id).?;
        }

        const result_type_id = typed_program.type_by_node_id.get(node.id).?;
        const continue_label = self.symbol_generator.generateLabel(label_names.continue_label);
        var incoming_values = std.ArrayList(PhiIncoming){};
        defer incoming_values.deinit(self.allocator);
        var continue_reachable = false;

        const else_label = if (decision_construct.else_arm != null)
            self.symbol_generator.generateLabel(label_names.else_arm)
        else
            null;

        if (decision_construct.arms.len == 0 and decision_construct.else_arm != null) {
            const else_arm = decision_construct.else_arm.?;
            const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
            if (else_result.exit_label) |exit_label| {
                continue_reachable = true;
                if (result_type_id != typed_program.type_store.unit_type_id) {
                    incoming_values.append(self.allocator, .{
                        .label = exit_label,
                        .register = else_result.register.?,
                    }) catch unreachable;
                }
                self.emitBranchInstruction(null, &.{continue_label});
            } else {
                return .{ .exit_label = null, .register = null };
            }
        } else {
            for (decision_construct.arms, 0..) |arm, index| {
                const arm_label = self.symbol_generator.generateLabel(label_names.arm);
                const is_last_arm = index + 1 == decision_construct.arms.len;
                const false_branches_to_continue = is_last_arm and
                    else_label == null and
                    !decision_construct.exhaustive_without_else;
                const false_label = if (!is_last_arm)
                    self.symbol_generator.generateLabel(label_names.next)
                else if (else_label) |label|
                    label
                else if (decision_construct.exhaustive_without_else)
                    null
                else
                    continue_label;

                if (false_branches_to_continue) {
                    continue_reachable = true;
                }

                if (is_last_arm and decision_construct.exhaustive_without_else and else_label == null) {
                    self.emitBranchInstruction(null, &.{arm_label});
                } else if (decision_construct.subject != null) {
                    const pattern_result = self.emitNode(
                        arm.condition,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (pattern_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }
                    current_label = pattern_result.exit_label.?;

                    const comparison_register = self.symbol_generator.generateRegister();
                    const comparison_instruction = std.fmt.allocPrint(
                        self.allocator,
                        "{s} = icmp eq {s} {s}, {s}",
                        .{
                            comparison_register,
                            llvmIrType(&typed_program.type_store, subject_type_id.?),
                            subject_register.?,
                            pattern_result.register.?,
                        },
                    ) catch unreachable;
                    self.lines.append(self.allocator, .{ .instruction = comparison_instruction }) catch unreachable;

                    self.emitBranchInstruction(comparison_register, &.{ arm_label, false_label.? });
                } else {
                    const condition_result = self.emitNode(
                        arm.condition,
                        current_label,
                        typed_program,
                        environment,
                    );
                    if (condition_result.exit_label == null) {
                        return .{ .exit_label = null, .register = null };
                    }
                    current_label = condition_result.exit_label.?;

                    self.emitBranchInstruction(condition_result.register.?, &.{ arm_label, false_label.? });
                }

                self.emitLabel(arm_label);
                const arm_result = self.emitNode(arm.body, arm_label, typed_program, environment);
                if (arm_result.exit_label) |exit_label| {
                    continue_reachable = true;
                    if (result_type_id != typed_program.type_store.unit_type_id) {
                        incoming_values.append(self.allocator, .{
                            .label = exit_label,
                            .register = arm_result.register.?,
                        }) catch unreachable;
                    }
                    self.emitBranchInstruction(null, &.{continue_label});
                }

                if (false_label) |next_label| {
                    if (!false_branches_to_continue) {
                        self.emitLabel(next_label);
                    }
                    current_label = next_label;
                } else {
                    current_label = arm_label;
                }
            }

            if (decision_construct.else_arm) |else_arm| {
                const else_result = self.emitNode(else_arm, current_label, typed_program, environment);
                if (else_result.exit_label) |exit_label| {
                    continue_reachable = true;
                    if (result_type_id != typed_program.type_store.unit_type_id) {
                        incoming_values.append(self.allocator, .{
                            .label = exit_label,
                            .register = else_result.register.?,
                        }) catch unreachable;
                    }
                    self.emitBranchInstruction(null, &.{continue_label});
                }
            }
        }

        if (!continue_reachable) {
            return .{ .exit_label = null, .register = null };
        }

        self.emitLabel(continue_label);
        if (result_type_id == typed_program.type_store.unit_type_id) {
            return .{
                .exit_label = continue_label,
                .register = null,
            };
        }
        if (incoming_values.items.len == 0) {
            return .{ .exit_label = null, .register = null };
        }
        if (incoming_values.items.len == 1) {
            return .{
                .exit_label = continue_label,
                .register = incoming_values.items[0].register,
            };
        }

        var phi_incoming_buffer = std.ArrayList(u8){};
        defer phi_incoming_buffer.deinit(self.allocator);
        for (incoming_values.items, 0..) |incoming, index| {
            if (index > 0) {
                phi_incoming_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
            }
            phi_incoming_buffer.writer(self.allocator).print(
                "[{s}, %{s}]",
                .{ incoming.register, incoming.label },
            ) catch unreachable;
        }

        const result_register = self.symbol_generator.generateRegister();
        const phi_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = phi {s} {s}",
            .{
                result_register,
                llvmIrType(&typed_program.type_store, result_type_id),
                phi_incoming_buffer.items,
            },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = phi_instruction }) catch unreachable;

        return .{
            .exit_label = continue_label,
            .register = result_register,
        };
    }

    fn emitLoopConstruct(
        self: *@This(),
        loop_construct: LoopConstruct,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        const loop_header_label = self.symbol_generator.generateLabel("loop_header");
        const loop_body_label = self.symbol_generator.generateLabel("loop_body");
        const loop_continue_label = self.symbol_generator.generateLabel("loop_continue");
        const loop_exit_label = self.symbol_generator.generateLabel("loop_exit");
        const previous_loop_context = environment.loop_context;
        const loop_context = LoopContext{
            .continue_label = loop_continue_label,
            .leave_label = loop_exit_label,
        };
        environment.loop_context = loop_context;

        // Loop header
        self.emitBranchInstruction(null, &.{loop_header_label});
        self.emitLabel(loop_header_label);
        if (loop_construct.condition) |condition| {
            const condition_result = self.emitNode(
                condition,
                loop_header_label,
                typed_program,
                environment,
            );
            if (condition_result.exit_label == null) {
                environment.loop_context = previous_loop_context;
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
            self.emitBranchInstruction(condition_result.register.?, &.{ loop_body_label, loop_exit_label });
        } else {
            self.emitBranchInstruction(null, &.{loop_body_label});
        }

        // Loop body
        self.emitLabel(loop_body_label);
        const body_result = self.emitBlock(loop_construct.body_block.*, loop_body_label, typed_program, environment);

        // Loop continue
        if (body_result.exit_label != null) {
            self.emitBranchInstruction(null, &.{loop_continue_label});
        }
        self.emitLabel(loop_continue_label);
        if (loop_construct.update) |update| {
            const update_result = self.emitNode(update, loop_continue_label, typed_program, environment);
            if (update_result.exit_label != null) {
                self.emitBranchInstruction(null, &.{loop_header_label});
            }
        } else {
            self.emitBranchInstruction(null, &.{loop_header_label});
        }

        self.emitLabel(loop_exit_label);
        environment.loop_context = previous_loop_context;

        return .{
            .exit_label = loop_exit_label,
            .register = null,
        };
    }

    fn emitBlock(
        self: *@This(),
        block: ast.Block,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        var current_label = entry_label;
        for (block.statements) |statement| {
            const emission_result = self.emitNode(&statement, current_label, typed_program, environment);
            if (emission_result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
        }

        // Emit the result expression if it exists
        var result_register: ?Register = null;
        if (block.result) |result_node| {
            const emission_result = self.emitNode(result_node, current_label, typed_program, environment);
            result_register = emission_result.register;
            if (emission_result.exit_label) |exit_label| {
                current_label = exit_label;
            } else {
                return .{
                    .exit_label = null,
                    .register = null,
                };
            }
        }

        return .{
            .exit_label = current_label,
            .register = result_register,
        };
    }

    fn emitLabel(self: *@This(), label: Label) void {
        self.lines.append(self.allocator, .{ .label = label }) catch unreachable;
    }

    fn emitBranchInstruction(self: *@This(), condition_register: ?Register, labels: []const Label) void {
        const instruction = switch (labels.len) {
            1 => std.fmt.allocPrint(
                self.allocator,
                "br label %{s}",
                .{labels[0]},
            ) catch unreachable,
            2 => std.fmt.allocPrint(
                self.allocator,
                "br i1 {s}, label %{s}, label %{s}",
                .{ condition_register orelse unreachable, labels[0], labels[1] },
            ) catch unreachable,
            else => unreachable,
        };
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }

    fn emitAlloca(self: *@This(), storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = alloca {s}",
            .{ storage, llvm_ir_type },
        ) catch unreachable;
        self.storage_allocation_instructions.append(self.allocator, instruction) catch unreachable;
    }

    fn emitStore(self: *@This(), value_register: Register, storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ llvm_ir_type, value_register, storage },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }

    fn emitLoad(self: *@This(), result_register: Register, storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = load {s}, ptr {s}",
            .{ result_register, llvm_ir_type, storage },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }
};
