const std = @import("std");

pub const Register = []const u8;
pub const Storage = []const u8;
pub const Label = []const u8;

const register_prefix = ".t";
const storage_prefix = ".s";

pub const FunctionSymbolGenerator = struct {
    allocator: std.mem.Allocator,
    register_counter: usize,
    storage_counter: usize,
    label_counter: usize,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .register_counter = 0,
            .storage_counter = 0,
            .label_counter = 0,
        };
    }

    pub fn reset(self: *@This()) void {
        self.register_counter = 0;
        self.storage_counter = 0;
        self.label_counter = 0;
    }

    pub fn generateRegister(self: *@This()) Register {
        const register = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ register_prefix, self.register_counter },
        ) catch unreachable;
        self.register_counter += 1;

        return register;
    }

    pub fn generateStorage(self: *@This()) Storage {
        const storage = std.fmt.allocPrint(
            self.allocator,
            "%{s}_{d}",
            .{ storage_prefix, self.storage_counter },
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
};
