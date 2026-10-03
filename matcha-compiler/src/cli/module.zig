const std = @import("std");

pub const command = @import("command.zig");
pub const parser = @import("parser.zig");
pub const runner = @import("runner.zig");

pub const run = runner.run;
pub const reportUnreportedError = runner.reportUnreportedError;

test {
    comptime referenceAllTestsRecursive(@import("parser.test.zig"));
}

/// Test blocks inside nested structs are only analyzed when the struct is referenced.
/// This references every public container in a test file, so nested scopes need `pub`.
fn referenceAllTestsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |declaration| {
        const value = @field(T, declaration.name);
        if (@TypeOf(value) == type and @typeInfo(value) == .@"struct") {
            referenceAllTestsRecursive(value);
        }
    }
}
