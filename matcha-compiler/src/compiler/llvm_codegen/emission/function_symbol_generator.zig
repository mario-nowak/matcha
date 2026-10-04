const std = @import("std");

pub const Value = []const u8;
pub const Address = []const u8;
pub const Label = []const u8;

/// Hands out the local names of one function. Every counter starts at zero in each function, so a name only
/// changes when its own function changes.
pub const FunctionSymbolGenerator = struct {
    allocator: std.mem.Allocator,
    value_counter: usize,
    synthetic_address_counter: usize,
    binding_address_counter_by_name: std.StringHashMap(usize),
    label_counter: usize,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .value_counter = 0,
            .synthetic_address_counter = 0,
            .binding_address_counter_by_name = std.StringHashMap(usize).init(allocator),
            .label_counter = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.binding_address_counter_by_name.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.value_counter = 0;
        self.synthetic_address_counter = 0;
        self.binding_address_counter_by_name.clearRetainingCapacity();
        self.label_counter = 0;
    }

    pub fn generateValueName(self: *@This()) Value {
        const value = std.fmt.allocPrint(self.allocator, "%value.{d}", .{self.value_counter}) catch unreachable;
        self.value_counter += 1;

        return value;
    }

    /// Names the address of a binding: a `val`, a `var`, a parameter, a `for` item or a payload binding.
    pub fn generateBindingAddressName(self: *@This(), binding_name: []const u8) Address {
        const counter = self.binding_address_counter_by_name.getOrPut(binding_name) catch unreachable;
        if (!counter.found_existing) {
            counter.value_ptr.* = 0;
        }
        const address = std.fmt.allocPrint(
            self.allocator,
            "%address.binding.{s}.{d}",
            .{ binding_name, counter.value_ptr.* },
        ) catch unreachable;
        counter.value_ptr.* += 1;

        return address;
    }

    /// Names an address that no binding owns, for example the index of a `for` loop or the result of a runtime call.
    pub fn generateSyntheticAddressName(self: *@This()) Address {
        const address = std.fmt.allocPrint(
            self.allocator,
            "%address.synthetic.{d}",
            .{self.synthetic_address_counter},
        ) catch unreachable;
        self.synthetic_address_counter += 1;

        return address;
    }

    /// Parameter names are unique within a function, so they need no counter.
    pub fn parameterName(self: *@This(), parameter_name: []const u8) Value {
        return std.fmt.allocPrint(self.allocator, "%parameter.{s}", .{parameter_name}) catch unreachable;
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
