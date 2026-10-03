const std = @import("std");

comptime {
    _ = @import("diagnostic_format.test.zig");
    _ = @import("syntax.test.zig");
    _ = @import("binding.test.zig");
    _ = @import("operator.test.zig");
    _ = @import("control_flow.test.zig");
    _ = @import("match.test.zig");
    _ = @import("functions.test.zig");
    _ = @import("strings.test.zig");
    _ = @import("arrays.test.zig");
    _ = @import("structures.test.zig");
    _ = @import("io.test.zig");
    _ = @import("runtime.test.zig");
    _ = @import("smoke.test.zig");
    _ = @import("unit_type.test.zig");
    referenceAllTestsRecursive(@import("cli.test.zig"));
    referenceAllTestsRecursive(@import("pattern_matching.test.zig"));
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
