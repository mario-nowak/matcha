const std = @import("std");
const ast = @import("ast");
const symbols = @import("symbols");
const typing = @import("typing");

const Register = []const u8;
const Instruction = []const u8;
const Label = []const u8;
const Storage = []const u8;
const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);
const LlvmIrTypeByMatchaType = std.EnumArray(typing.Type, []const u8);

const llvm_string_type_definition = "%String = type { i8*, i64 }";
const print_int_formatting_string = ".print_int_formatting_string";
const print_string_newline = ".print_string_newline";

const StringLiteralGlobal = struct {
    name: []const u8,
    content: []const u8,
    len: usize,
};

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

const llvm_ir_type_by_matcha_type = LlvmIrTypeByMatchaType.init(.{
    .Unit = "void",
    .Boolean = "i1",
    .Integer = "i64",
    .String = "%String",
});

const LoopContext = struct {
    continue_label: Label,
    leave_label: Label,
};

const LoopConstruct = struct {
    condition: ?*ast.Node,
    update: ?*ast.Node,
    body_block: *ast.Block,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,
    function_return_type: typing.Type,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
        function_return_type: typing.Type,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
            .function_return_type = function_return_type,
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
};

pub const LlvmIrEmitter = struct {
    allocator: std.mem.Allocator,
    symbol_generator: SymbolGenerator,
    storage_allocation_instructions: std.ArrayList(Instruction),
    lines: std.ArrayList(Line),
    string_literal_globals: std.ArrayList(StringLiteralGlobal),
    string_literal_global_name_by_node_id: std.AutoHashMap(ast.NodeId, []const u8),
    needs_printf: bool,
    needs_write: bool,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbol_generator = SymbolGenerator.init(allocator, ".t", ".s"),
            .lines = .{},
            .storage_allocation_instructions = .{},
            .string_literal_globals = .{},
            .string_literal_global_name_by_node_id = std.AutoHashMap(ast.NodeId, []const u8).init(allocator),
            .needs_printf = false,
            .needs_write = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
        self.storage_allocation_instructions.deinit(self.allocator);
        self.string_literal_globals.deinit(self.allocator);
        self.string_literal_global_name_by_node_id.deinit();
    }

    pub fn emitLlvmIr(self: *@This(), typed_program: *const typing.TypedProgram) []const u8 {
        self.needs_printf = false;
        self.needs_write = false;
        self.symbol_generator.string_literal_counter = 0;
        self.string_literal_globals.clearRetainingCapacity();
        self.string_literal_global_name_by_node_id.clearRetainingCapacity();

        var user_defined_functions = std.ArrayList([]const u8){};
        defer user_defined_functions.deinit(self.allocator);
        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .FunctionDefinition => {
                    const function_ir = self.emitFunctionDefinition(statement, typed_program);
                    user_defined_functions.append(self.allocator, function_ir) catch unreachable;
                },
                else => {},
            }
        }

        const main_function_ir = self.emitMainFunction(typed_program);
        const builtin_print_string_ir = if (self.needs_write)
            self.emitBuiltinPrintStringFunction()
        else
            null;
        const builtin_print_int_ir = if (self.needs_printf)
            self.emitBuiltinPrintIntFunction()
        else
            null;

        var sections = std.ArrayList([]const u8){};
        defer sections.deinit(self.allocator);
        sections.append(self.allocator, self.renderModulePreamble()) catch unreachable;
        if (builtin_print_string_ir) |ir| {
            sections.append(self.allocator, ir) catch unreachable;
        }
        if (builtin_print_int_ir) |ir| {
            sections.append(self.allocator, ir) catch unreachable;
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

    fn renderModulePreamble(self: *@This()) []const u8 {
        var module_preamble_buffer = std.ArrayList(u8){};
        defer module_preamble_buffer.deinit(self.allocator);
        module_preamble_buffer.writer(self.allocator).print("{s}", .{llvm_string_type_definition}) catch unreachable;

        const string_literal_globals_ir = self.renderStringLiteralGlobals();
        if (string_literal_globals_ir.len > 0 or self.needs_write or self.needs_printf) {
            module_preamble_buffer.writer(self.allocator).print("\n\n", .{}) catch unreachable;
        }
        if (string_literal_globals_ir.len > 0) {
            module_preamble_buffer.writer(self.allocator).print("{s}", .{string_literal_globals_ir}) catch unreachable;
        }
        if (self.needs_write) {
            if (string_literal_globals_ir.len > 0) {
                module_preamble_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
            module_preamble_buffer.writer(self.allocator).print(
                "@{s} = private unnamed_addr constant [1 x i8] c\"\\0A\"",
                .{print_string_newline},
            ) catch unreachable;
        }
        if (self.needs_printf) {
            if (string_literal_globals_ir.len > 0 or self.needs_write) {
                module_preamble_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
            module_preamble_buffer.writer(self.allocator).print(
                "@.print_int_formatting_string = private unnamed_addr constant [4 x i8] c\"%d\\0A\\00\"",
                .{},
            ) catch unreachable;
        }

        if (self.needs_write or self.needs_printf) {
            module_preamble_buffer.writer(self.allocator).print("\n\n", .{}) catch unreachable;
        }
        if (self.needs_write) {
            module_preamble_buffer.writer(self.allocator).print("declare i64 @write(i32, i8*, i64)", .{}) catch unreachable;
        }
        if (self.needs_printf) {
            if (self.needs_write) {
                module_preamble_buffer.writer(self.allocator).print("\n", .{}) catch unreachable;
            }
            module_preamble_buffer.writer(self.allocator).print("declare i32 @printf(i8*, ...)", .{}) catch unreachable;
        }

        return std.fmt.allocPrint(self.allocator, "{s}", .{module_preamble_buffer.items}) catch unreachable;
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

        var environment = Environment.init(self.allocator, null, .Integer);
        defer environment.deinit();
        var current_label: Label = "entry";

        for (typed_program.resolved_program.program.statements) |*statement| {
            switch (statement.kind) {
                .FunctionDefinition => continue,
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
        function_node: *const ast.Node,
        typed_program: *const typing.TypedProgram,
    ) []const u8 {
        const function_definition = switch (function_node.kind) {
            .FunctionDefinition => |function_definition| function_definition,
            else => unreachable,
        };

        self.resetCurrentFunctionState();

        const function_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(function_node.id) orelse unreachable;
        const function_symbol = typed_program.resolved_program.symbol_table.getSymbol(function_symbol_id);
        const function_return_type = typed_program.type_by_symbol_id.get(function_symbol_id) orelse unreachable;
        const function_return_llvm_ir_type = llvm_ir_type_by_matcha_type.get(function_return_type);
        const parameter_symbol_ids = typed_program.resolved_program.parameter_symbol_ids_by_function_symbol_id.get(
            function_symbol_id,
        ) orelse unreachable;

        var parameter_list_buffer = std.ArrayList(u8){};
        defer parameter_list_buffer.deinit(self.allocator);
        var environment = Environment.init(self.allocator, null, function_return_type);
        defer environment.deinit();

        for (parameter_symbol_ids, 0..) |parameter_symbol_id, index| {
            const parameter_symbol = typed_program.resolved_program.symbol_table.getSymbol(parameter_symbol_id);
            const parameter_type = typed_program.type_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
            const parameter_llvm_ir_type = llvm_ir_type_by_matcha_type.get(parameter_type);
            const parameter_register = std.fmt.allocPrint(
                self.allocator,
                "%arg_{d}_{s}",
                .{ index, parameter_symbol.name },
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
            environment.storage_by_symbol_id.put(parameter_symbol_id, storage) catch unreachable;
        }

        const body_result = self.emitNode(
            function_definition.body_expression,
            "entry",
            typed_program,
            &environment,
        );

        if (body_result.exit_label != null) {
            switch (function_return_type) {
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
            self.getLlvmFunctionName(function_symbol),
            function_return_llvm_ir_type,
            parameter_list_buffer.items,
        );
    }

    fn emitBuiltinPrintIntFunction(self: *@This()) []const u8 {
        self.resetCurrentFunctionState();

        const formatting_string_pointer = self.symbol_generator.generateRegister();
        const formatting_string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [4 x i8], [4 x i8]* @.print_int_formatting_string, i64 0, i64 0",
            .{formatting_string_pointer},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = formatting_string_instruction }) catch unreachable;

        const print_instruction = std.fmt.allocPrint(
            self.allocator,
            "call i32 (i8*, ...) @printf(i8* {s}, i64 %arg_0_value)",
            .{formatting_string_pointer},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = print_instruction }) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = "ret void" }) catch unreachable;

        return self.renderCurrentFunction("builtin_printInt", "void", "i64 %arg_0_value");
    }

    fn emitBuiltinPrintStringFunction(self: *@This()) []const u8 {
        self.resetCurrentFunctionState();

        const pointer_register = self.symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String %arg_0_value, 0",
            .{pointer_register},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = pointer_instruction }) catch unreachable;

        const length_register = self.symbol_generator.generateRegister();
        const length_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = extractvalue %String %arg_0_value, 1",
            .{length_register},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = length_instruction }) catch unreachable;

        const print_instruction = std.fmt.allocPrint(
            self.allocator,
            "call i64 @write(i32 1, i8* {s}, i64 {s})",
            .{ pointer_register, length_register },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = print_instruction }) catch unreachable;

        const newline_pointer_register = self.symbol_generator.generateRegister();
        const newline_pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [1 x i8], [1 x i8]* @{s}, i64 0, i64 0",
            .{ newline_pointer_register, print_string_newline },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = newline_pointer_instruction }) catch unreachable;

        const newline_instruction = std.fmt.allocPrint(
            self.allocator,
            "call i64 @write(i32 1, i8* {s}, i64 1)",
            .{newline_pointer_register},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = newline_instruction }) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = "ret void" }) catch unreachable;

        return self.renderCurrentFunction("builtin_printString", "void", "%String %arg_0_value");
    }

    fn getLlvmFunctionName(self: *@This(), symbol: symbols.Symbol) []const u8 {
        switch (symbol.kind) {
            .Function => |function_info| switch (function_info.implementation) {
                .BuiltinPrintInt => return "builtin_printInt",
                .BuiltinPrintString => return "builtin_printString",
                .UserDefined => {
                    return std.fmt.allocPrint(
                        self.allocator,
                        "matcha_{d}_{s}",
                        .{ symbol.id, symbol.name },
                    ) catch unreachable;
                },
            },
            else => unreachable,
        }
    }

    fn emitNode(
        self: *@This(),
        node: *const ast.Node,
        entry_label: Label,
        typed_program: *const typing.TypedProgram,
        environment: *Environment,
    ) EmissionResult {
        switch (node.kind) {
            .FunctionDefinition => {
                return .{
                    .exit_label = entry_label,
                    .register = null,
                };
            },
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
                            llvm_ir_type_by_matcha_type.get(environment.function_return_type),
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
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(typed_program.type_by_node_id.get(node.id).?);
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
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{environment.loop_context.?.leave_label},
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = branch_instruction }) catch unreachable;

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .Continue => {
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{environment.loop_context.?.continue_label},
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = branch_instruction }) catch unreachable;

                return .{
                    .exit_label = null,
                    .register = null,
                };
            },
            .CallExpression => |call_expression| {
                const callee_symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(
                    call_expression.callee.id,
                ) orelse unreachable;
                const callee_symbol = typed_program.resolved_program.symbol_table.getSymbol(callee_symbol_id);
                const function_info = switch (callee_symbol.kind) {
                    .Function => |function_info| function_info,
                    else => unreachable,
                };
                if (function_info.implementation == .BuiltinPrintInt) {
                    self.needs_printf = true;
                } else if (function_info.implementation == .BuiltinPrintString) {
                    self.needs_write = true;
                }

                const parameter_symbol_ids = typed_program.resolved_program.parameter_symbol_ids_by_function_symbol_id.get(
                    callee_symbol_id,
                ) orelse unreachable;
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

                var argument_list_buffer = std.ArrayList(u8){};
                defer argument_list_buffer.deinit(self.allocator);
                for (parameter_symbol_ids, argument_registers.items, 0..) |parameter_symbol_id, argument_register, index| {
                    const parameter_type = typed_program.type_by_symbol_id.get(parameter_symbol_id) orelse unreachable;
                    if (index > 0) {
                        argument_list_buffer.writer(self.allocator).print(", ", .{}) catch unreachable;
                    }
                    argument_list_buffer.writer(self.allocator).print(
                        "{s} {s}",
                        .{
                            llvm_ir_type_by_matcha_type.get(parameter_type),
                            argument_register,
                        },
                    ) catch unreachable;
                }

                const function_name = self.getLlvmFunctionName(callee_symbol);
                const function_return_type = typed_program.type_by_symbol_id.get(callee_symbol_id) orelse unreachable;
                const function_return_llvm_ir_type = llvm_ir_type_by_matcha_type.get(function_return_type);
                if (function_return_type == .Unit) {
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
                const instruction_type = llvm_ir_type_by_matcha_type.get(left_operand_type);
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
                const instruction_type = llvm_ir_type_by_matcha_type.get(operation_type);
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
                const value_type = typed_program.type_by_node_id.get(value_declaration.value.id).?;
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(value_type);

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
                const value_result = self.emitNode(
                    assignment.value,
                    entry_label,
                    typed_program,
                    environment,
                );
                const symbol_id = typed_program.resolved_program.symbol_id_by_node_id.get(node.id).?;
                const storage = environment.storage_by_symbol_id.get(symbol_id).?;
                const value_type = typed_program.type_by_node_id.get(assignment.value.id).?;
                const llvm_ir_type = llvm_ir_type_by_matcha_type.get(value_type);
                self.emitStore(value_result.register.?, storage, llvm_ir_type);

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
                // Emit condition expression
                const condition_result = self.emitNode(
                    if_statement.condition,
                    entry_label,
                    typed_program,
                    environment,
                );

                const then_label = self.symbol_generator.generateLabel("then");
                const continue_label = self.symbol_generator.generateLabel("continue");
                const branch_continue_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{continue_label},
                ) catch unreachable;

                // Emit branch instruction
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br i1 {s}, label %{s}, label %{s}",
                    .{ condition_result.register.?, then_label, continue_label },
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = branch_instruction }) catch unreachable;

                // "then" path
                self.emitLabel(then_label);
                const then_result = self.emitNode(if_statement.then_branch, then_label, typed_program, environment);
                if (then_result.exit_label) |_| {
                    self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction }) catch unreachable;
                }

                self.emitLabel(continue_label);

                return .{
                    .exit_label = continue_label,
                    .register = null,
                };
            },
            .IfExpression => |if_expression| {
                // Emit condition expression
                const condition_result = self.emitNode(
                    if_expression.condition,
                    entry_label,
                    typed_program,
                    environment,
                );

                const then_label = self.symbol_generator.generateLabel("then");
                const else_label = self.symbol_generator.generateLabel("else");
                const continue_label = self.symbol_generator.generateLabel("continue");
                const branch_continue_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br label %{s}",
                    .{continue_label},
                ) catch unreachable;

                // Emit branch instruction
                const branch_instruction = std.fmt.allocPrint(
                    self.allocator,
                    "br i1 {s}, label %{s}, label %{s}",
                    .{ condition_result.register.?, then_label, else_label },
                ) catch unreachable;
                self.lines.append(self.allocator, .{ .instruction = branch_instruction }) catch unreachable;

                // "then" path
                self.emitLabel(then_label);
                const then_result = self.emitNode(
                    if_expression.then_block,
                    then_label,
                    typed_program,
                    environment,
                );
                const then_falls_through = then_result.exit_label != null;
                if (then_falls_through) {
                    self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction }) catch unreachable;
                }

                // "else" path
                self.emitLabel(else_label);
                const else_result = self.emitNode(
                    if_expression.else_block,
                    else_label,
                    typed_program,
                    environment,
                );
                const else_falls_through = else_result.exit_label != null;
                if (else_falls_through) {
                    self.lines.append(self.allocator, .{ .instruction = branch_continue_instruction }) catch unreachable;
                }

                if (!then_falls_through and !else_falls_through) {
                    return .{
                        .exit_label = null,
                        .register = null,
                    };
                }

                // "continue" path
                self.emitLabel(continue_label);
                const result_type = typed_program.type_by_node_id.get(node.id).?;
                if (result_type == .Unit) {
                    return .{
                        .exit_label = continue_label,
                        .register = null,
                    };
                } else {
                    const result_register = self.symbol_generator.generateRegister();
                    const instruction_type = llvm_ir_type_by_matcha_type.get(result_type);
                    if (then_falls_through and else_falls_through) {
                        const phi_instruction = std.fmt.allocPrint(
                            self.allocator,
                            "{s} = phi {s} [{s}, %{s}], [{s}, %{s}]",
                            .{
                                result_register,
                                instruction_type,
                                then_result.register.?,
                                then_result.exit_label.?,
                                else_result.register.?,
                                else_result.exit_label.?,
                            },
                        ) catch unreachable;
                        self.lines.append(self.allocator, .{ .instruction = phi_instruction }) catch unreachable;

                        return .{
                            .exit_label = continue_label,
                            .register = result_register,
                        };
                    }

                    return .{
                        .exit_label = continue_label,
                        .register = if (then_falls_through) then_result.register else else_result.register,
                    };
                }
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
        }
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
        const branch_to_header_instruction = std.fmt.allocPrint(
            self.allocator,
            "br label %{s}",
            .{loop_header_label},
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = branch_to_header_instruction }) catch unreachable;
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
            const branch_instruction = std.fmt.allocPrint(
                self.allocator,
                "br i1 {s}, label %{s}, label %{s}",
                .{ condition_result.register.?, loop_body_label, loop_exit_label },
            ) catch unreachable;
            self.lines.append(self.allocator, .{ .instruction = branch_instruction }) catch unreachable;
        } else {
            const branch_to_body_instruction = std.fmt.allocPrint(
                self.allocator,
                "br label %{s}",
                .{loop_body_label},
            ) catch unreachable;
            self.lines.append(self.allocator, .{ .instruction = branch_to_body_instruction }) catch unreachable;
        }

        // Loop body
        self.emitLabel(loop_body_label);
        const body_result = self.emitBlock(loop_construct.body_block.*, loop_body_label, typed_program, environment);

        // Loop continue
        const branch_to_continue_instruction = std.fmt.allocPrint(
            self.allocator,
            "br label %{s}",
            .{loop_continue_label},
        ) catch unreachable;
        if (body_result.exit_label != null) {
            self.lines.append(self.allocator, .{ .instruction = branch_to_continue_instruction }) catch unreachable;
        }
        self.emitLabel(loop_continue_label);
        if (loop_construct.update) |update| {
            const update_result = self.emitNode(update, loop_continue_label, typed_program, environment);
            if (update_result.exit_label != null) {
                self.lines.append(self.allocator, .{ .instruction = branch_to_header_instruction }) catch unreachable;
            }
        } else {
            self.lines.append(self.allocator, .{ .instruction = branch_to_header_instruction }) catch unreachable;
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
            "store {s} {s}, {s}* {s}",
            .{ llvm_ir_type, value_register, llvm_ir_type, storage },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }

    fn emitLoad(self: *@This(), result_register: Register, storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = load {s}, {s}* {s}",
            .{ result_register, llvm_ir_type, llvm_ir_type, storage },
        ) catch unreachable;
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }
};
