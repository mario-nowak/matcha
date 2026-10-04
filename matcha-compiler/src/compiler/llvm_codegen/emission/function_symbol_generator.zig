const std = @import("std");

pub const Value = []const u8;
pub const Address = []const u8;
pub const Label = []const u8;

const value_prefix = ".t";
const address_prefix = ".s";

pub const FunctionSymbolGenerator = struct {
    allocator: std.mem.Allocator,
    value_counter: usize,
    address_counter: usize,
    label_counter: usize,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .value_counter = 0,
            .address_counter = 0,
            .label_counter = 0,
        };
    }

    pub fn deinit(self: *const @This()) void {
        _ = self;
    }

    pub fn reset(self: *@This()) void {
        self.value_counter = 0;
        self.address_counter = 0;
        self.label_counter = 0;
    }

    pub fn generateValue(self: *@This()) Value {
        const value = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ value_prefix, self.value_counter },
        ) catch unreachable;
        self.value_counter += 1;

        return value;
    }

    pub fn generateAddress(self: *@This()) Address {
        const address = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ address_prefix, self.address_counter },
        ) catch unreachable;
        self.address_counter += 1;

        return address;
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
};
