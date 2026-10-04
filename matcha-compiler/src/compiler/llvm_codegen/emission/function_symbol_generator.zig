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
    construct_counter_by_name: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .value_counter = 0,
            .synthetic_address_counter = 0,
            .binding_address_counter_by_name = std.StringHashMap(usize).init(allocator),
            .construct_counter_by_name = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.binding_address_counter_by_name.deinit();
        self.construct_counter_by_name.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.value_counter = 0;
        self.synthetic_address_counter = 0;
        self.binding_address_counter_by_name.clearRetainingCapacity();
        self.construct_counter_by_name.clearRetainingCapacity();
    }

    pub fn generateValueName(self: *@This()) Value {
        const value = std.fmt.allocPrint(self.allocator, "%value.{d}", .{self.value_counter}) catch unreachable;
        self.value_counter += 1;

        return value;
    }

    /// Names the address of a binding: a `val`, a `var`, a parameter, a `for` item or a payload binding.
    pub fn generateBindingAddressName(self: *@This(), binding_name: []const u8) Address {
        const binding_number = nextNumber(&self.binding_address_counter_by_name, binding_name);
        return std.fmt.allocPrint(self.allocator, "%address.binding.{s}.{d}", .{ binding_name, binding_number }) catch unreachable;
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

    /// Starts the labels of one control-flow construct, for example the third `match` of the function.
    pub fn generateConstructLabels(self: *@This(), construct_name: []const u8) ConstructLabels {
        return .{
            .allocator = self.allocator,
            .construct_name = construct_name,
            .construct_number = nextNumber(&self.construct_counter_by_name, construct_name),
        };
    }

    fn nextNumber(counter_by_name: *std.StringHashMap(usize), name: []const u8) usize {
        const counter = counter_by_name.getOrPut(name) catch unreachable;
        if (!counter.found_existing) {
            counter.value_ptr.* = 0;
        }
        const number = counter.value_ptr.*;
        counter.value_ptr.* += 1;

        return number;
    }
};

/// The labels of one control-flow construct: `<construct>.<number>.<role>`.
pub const ConstructLabels = struct {
    allocator: std.mem.Allocator,
    construct_name: []const u8,
    construct_number: usize,

    pub fn role(self: @This(), role_name: []const u8) Label {
        return std.fmt.allocPrint(self.allocator, "{s}.{d}.{s}", .{ self.construct_name, self.construct_number, role_name }) catch unreachable;
    }

    pub fn arm(self: @This(), arm_index: usize) Label {
        return std.fmt.allocPrint(self.allocator, "{s}.{d}.arm.{d}", .{ self.construct_name, self.construct_number, arm_index }) catch unreachable;
    }

    /// Names the block that checks whether an arm matches.
    pub fn armCondition(self: @This(), arm_index: usize) Label {
        return std.fmt.allocPrint(self.allocator, "{s}.{d}.arm.{d}.condition", .{ self.construct_name, self.construct_number, arm_index }) catch unreachable;
    }
};
