const std = @import("std");
const ast = @import("ast");

const function_emission = @import("function_emission");

const Register = function_emission.Register;
const FunctionIrBuilder = function_emission.FunctionIrBuilder;
const FunctionSymbolGenerator = function_emission.FunctionSymbolGenerator;

const StringLiteralGlobal = struct {
    name: []const u8,
    content: []const u8,
    len: usize,
};

pub const StringLiteralEmitter = struct {
    allocator: std.mem.Allocator,
    string_literal_globals: std.ArrayList(StringLiteralGlobal),
    string_literal_global_name_by_node_id: std.AutoHashMap(ast.NodeId, []const u8),
    string_literal_global_counter: usize,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .string_literal_globals = .{},
            .string_literal_global_name_by_node_id = std.AutoHashMap(ast.NodeId, []const u8).init(allocator),
            .string_literal_global_counter = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.string_literal_globals.deinit(self.allocator);
        self.string_literal_global_name_by_node_id.deinit();
    }

    pub fn resetModuleState(self: *@This()) void {
        self.string_literal_globals.clearRetainingCapacity();
        self.string_literal_global_name_by_node_id.clearRetainingCapacity();
        self.string_literal_global_counter = 0;
    }

    pub fn renderGlobals(self: *@This()) []const u8 {
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

    pub fn emitStringLiteralValue(
        self: *@This(),
        node_id: ast.NodeId,
        content: []const u8,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const global_name = self.ensureStringLiteralGlobalName(node_id, content);
        const pointer_register = self.emitStringLiteralPointer(global_name, content.len, function_symbol_generator, builder);
        return self.emitStringValue(pointer_register, content.len, function_symbol_generator, builder);
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

    fn ensureStringLiteralGlobalName(
        self: *@This(),
        node_id: ast.NodeId,
        content: []const u8,
    ) []const u8 {
        if (self.string_literal_global_name_by_node_id.get(node_id)) |existing_global_name| {
            return existing_global_name;
        }

        const global_name = self.generateStringLiteralGlobalName();
        self.string_literal_globals.append(self.allocator, .{
            .name = global_name,
            .content = content,
            .len = content.len,
        }) catch unreachable;
        self.string_literal_global_name_by_node_id.put(node_id, global_name) catch unreachable;

        return global_name;
    }

    fn emitStringLiteralPointer(
        self: *@This(),
        global_name: []const u8,
        len: usize,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const pointer_register = function_symbol_generator.generateRegister();
        const pointer_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds [{d} x i8], [{d} x i8]* {s}, i64 0, i64 0",
            .{ pointer_register, len, len, global_name },
        ) catch unreachable;
        builder.emitInstruction(pointer_instruction);

        return pointer_register;
    }

    fn emitStringValue(
        self: *@This(),
        pointer_register: Register,
        len: usize,
        function_symbol_generator: *FunctionSymbolGenerator,
        builder: *FunctionIrBuilder,
    ) Register {
        const partial_string_register = function_symbol_generator.generateRegister();
        const partial_string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String undef, i8* {s}, 0",
            .{ partial_string_register, pointer_register },
        ) catch unreachable;
        builder.emitInstruction(partial_string_instruction);

        const string_register = function_symbol_generator.generateRegister();
        const string_instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = insertvalue %String {s}, i64 {d}, 1",
            .{ string_register, partial_string_register, len },
        ) catch unreachable;
        builder.emitInstruction(string_instruction);

        return string_register;
    }

    fn generateStringLiteralGlobalName(self: *@This()) []const u8 {
        const global_name = std.fmt.allocPrint(
            self.allocator,
            "@.string_literal_{d}",
            .{self.string_literal_global_counter},
        ) catch unreachable;
        self.string_literal_global_counter += 1;

        return global_name;
    }
};
