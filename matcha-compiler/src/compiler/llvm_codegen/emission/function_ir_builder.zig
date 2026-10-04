const std = @import("std");

pub const Instruction = []const u8;
pub const Label = []const u8;
pub const Address = []const u8;

const entry_label: Label = "entry";

const Line = union(enum) {
    instruction: Instruction,
    label: Label,
};

/// Builds the body of a single LLVM IR function while tracking the current
/// insertion point. `current_label` names the basic block instructions are
/// appended to; it becomes null after a terminator, which marks the code that
/// follows as unreachable. Instructions emitted while unreachable are dropped,
/// so callers never have to thread reachability through their control flow.
pub const FunctionIrBuilder = struct {
    allocator: std.mem.Allocator,
    stack_allocation_instructions: std.ArrayList(Instruction),
    lines: std.ArrayList(Line),
    current_label: ?Label,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .stack_allocation_instructions = .{},
            .lines = .{},
            .current_label = entry_label,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
        self.stack_allocation_instructions.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.deinit();
        self.lines = .{};
        self.stack_allocation_instructions = .{};
        self.current_label = entry_label;
    }

    /// The label of the basic block currently being emitted into, or null when
    /// the last emitted instruction was a terminator and no label followed.
    pub fn currentLabel(self: *const @This()) ?Label {
        return self.current_label;
    }

    pub fn render(
        self: *@This(),
        function_name: []const u8,
        return_llvm_ir_type: []const u8,
        parameter_list: []const u8,
    ) []const u8 {
        var stack_allocation_buffer = std.ArrayList(u8){};
        defer stack_allocation_buffer.deinit(self.allocator);
        for (self.stack_allocation_instructions.items) |instruction| {
            stack_allocation_buffer.writer(self.allocator).print("    {s}\n", .{instruction}) catch unreachable;
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
            \\{s}{s}}}
        ,
            .{
                return_llvm_ir_type,
                function_name,
                parameter_list,
                stack_allocation_buffer.items,
                instructions_buffer.items,
            },
        ) catch unreachable;
    }

    pub fn emitLabel(self: *@This(), label: Label) void {
        self.lines.append(self.allocator, .{ .label = label }) catch unreachable;
        self.current_label = label;
    }

    pub fn emitInstruction(self: *@This(), instruction: Instruction) void {
        if (self.current_label == null) {
            return;
        }
        self.lines.append(self.allocator, .{ .instruction = instruction }) catch unreachable;
    }

    /// Emits an instruction that ends the current basic block (ret, br,
    /// unreachable). Everything emitted afterwards is dropped until the next
    /// label opens a new block.
    pub fn emitTerminatorInstruction(self: *@This(), instruction: Instruction) void {
        self.emitInstruction(instruction);
        self.current_label = null;
    }

    pub fn emitBranchInstruction(self: *@This(), condition_value: ?[]const u8, labels: []const Label) void {
        const instruction = switch (labels.len) {
            1 => std.fmt.allocPrint(
                self.allocator,
                "br label %{s}",
                .{labels[0]},
            ) catch unreachable,
            2 => std.fmt.allocPrint(
                self.allocator,
                "br i1 {s}, label %{s}, label %{s}",
                .{ condition_value orelse unreachable, labels[0], labels[1] },
            ) catch unreachable,
            else => unreachable,
        };
        self.emitTerminatorInstruction(instruction);
    }

    pub fn emitStackAllocation(self: *@This(), address: Address, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = alloca {s}",
            .{ address, llvm_ir_type },
        ) catch unreachable;
        self.stack_allocation_instructions.append(self.allocator, instruction) catch unreachable;
    }

    pub fn emitStore(self: *@This(), stored_value: []const u8, address: Address, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "store {s} {s}, ptr {s}",
            .{ llvm_ir_type, stored_value, address },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }

    /// Emits a pointer to the field at `field_index` of the structure type `%<llvm_type_name>` that `base_value` points to.
    pub fn emitFieldPointer(
        self: *@This(),
        result_value: []const u8,
        llvm_type_name: []const u8,
        base_value: []const u8,
        field_index: u32,
    ) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds %{s}, ptr {s}, i32 0, i32 {d}",
            .{ result_value, llvm_type_name, base_value, field_index },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }

    /// Emits a pointer to the element at `index` of the `element_llvm_type` values that `base_value` points to.
    pub fn emitElementPointer(
        self: *@This(),
        result_value: []const u8,
        element_llvm_type: []const u8,
        base_value: []const u8,
        index: []const u8,
    ) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = getelementptr inbounds {s}, ptr {s}, i64 {s}",
            .{ result_value, element_llvm_type, base_value, index },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }

    pub fn emitLoad(self: *@This(), result_value: []const u8, address: Address, llvm_ir_type: []const u8) void {
        const instruction = std.fmt.allocPrint(
            self.allocator,
            "{s} = load {s}, ptr {s}",
            .{ result_value, llvm_ir_type, address },
        ) catch unreachable;
        self.emitInstruction(instruction);
    }
};
