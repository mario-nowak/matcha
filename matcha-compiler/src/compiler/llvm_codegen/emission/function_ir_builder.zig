const std = @import("std");

pub const Instruction = []const u8;
pub const Label = []const u8;
pub const Storage = []const u8;

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

pub const FunctionIrBuilder = struct {
    allocator: std.mem.Allocator,
    storage_allocation_instructions: std.ArrayList(Instruction),
    lines: std.ArrayList(Line),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .storage_allocation_instructions = .{},
            .lines = .{},
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
        self.storage_allocation_instructions.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.deinit();
        self.lines = .{};
        self.storage_allocation_instructions = .{};
    }

    pub fn render(
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

    pub fn emitLabel(self: *@This(), label: Label) void {
        self.lines.append(self.allocator, .{ .label = label }) catch unreachable;
    }

    pub fn emitInstruction(self: *@This(), instruction: Instruction) void {
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }

    pub fn emitStorageAllocationInstruction(self: *@This(), instruction: Instruction) void {
        self.storage_allocation_instructions.append(self.allocator, instruction) catch unreachable;
    }

    pub fn emitBranchInstruction(self: *@This(), condition_register: ?[]const u8, labels: []const Label) void {
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
        self.emitInstruction(instruction);
    }

    pub fn emitAlloca(self: *@This(), storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = alloca {s}",
            .{ storage, llvm_ir_type },
        ) catch unreachable;
        self.emitStorageAllocationInstruction(instruction);
    }

    pub fn emitStore(self: *@This(), value_register: []const u8, storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ llvm_ir_type, value_register, storage },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }

    pub fn emitLoad(self: *@This(), result_register: []const u8, storage: Storage, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = load {s}, ptr {s}",
            .{ result_register, llvm_ir_type, storage },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }
};
