const std = @import("std");

pub fn expect(actual: anytype) Expectation(@TypeOf(actual)) {
    return .{ .actual = actual };
}

// Return a wrapper type for the actual value's type. No allocation is needed.
fn Expectation(comptime T: type) type {
    return struct {
        actual: T,

        // Expected structs specify fields to compare. Omitted fields remain unchecked.
        // Expected tuples match entire slices, including their length and element order.
        pub fn toMatch(self: @This(), expected: anytype) error{TestExpectedEqual}!void {
            try expectValue(self.actual, expected);
        }
    };
}

fn expectValue(actual: anytype, expected: anytype) error{TestExpectedEqual}!void {
    // Types are known at compile time. Actual values are checked at runtime.
    const Actual = @TypeOf(actual);
    const Expected = @TypeOf(expected);
    switch (@typeInfo(Actual)) {
        .@"struct" => {
            if (@typeInfo(Expected) != .@"struct") {
                @compileError("expect a struct-shaped value for " ++ @typeName(Actual));
            }
            // Each iteration uses a different field name and potentially a different type.
            // `inline for` generates a comparison for each expected field at compile time.
            inline for (std.meta.fields(Expected)) |field| {
                if (!@hasField(Actual, field.name)) {
                    @compileError("unknown field '" ++ field.name ++ "' on " ++ @typeName(Actual));
                }
                expectValue(@field(actual, field.name), @field(expected, field.name)) catch |err| {
                    std.debug.print("Mismatch in field '{s}'\n", .{field.name});
                    return err;
                };
            }
        },
        .@"union" => |info| {
            const Tag = info.tag_type orelse @compileError("structural matching requires tagged unions");
            // A bare enum literal can match a case with no payload.
            if (@typeInfo(Expected) == .enum_literal) {
                const case_name = @tagName(expected);
                if (!@hasField(Actual, case_name)) {
                    @compileError("unknown union case '" ++ case_name ++ "' on " ++ @typeName(Actual));
                }
                if (@TypeOf(@field(actual, case_name)) != void) {
                    @compileError("provide a payload expectation for union case '" ++ case_name ++ "'");
                }
                return std.testing.expectEqual(@as(Tag, expected), std.meta.activeTag(actual));
            }
            if (@typeInfo(Expected) != .@"struct" or std.meta.fields(Expected).len != 1) {
                @compileError("expect exactly one case for " ++ @typeName(Actual));
            }
            const case_name = std.meta.fields(Expected)[0].name;
            if (!@hasField(Actual, case_name)) {
                @compileError("unknown union case '" ++ case_name ++ "' on " ++ @typeName(Actual));
            }
            // Check the active tag before reading its payload.
            try std.testing.expectEqual(@field(Tag, case_name), std.meta.activeTag(actual));
            try expectValue(@field(actual, case_name), @field(expected, case_name));
        },
        .pointer => |info| switch (info.size) {
            // The expectation describes the pointed-to value, not an address.
            .one => try expectValue(actual.*, expected),
            .slice => {
                if (info.child == u8) {
                    return std.testing.expectEqualStrings(expected, actual);
                }
                if (@typeInfo(Expected) != .@"struct" or !@typeInfo(Expected).@"struct".is_tuple) {
                    @compileError("expect a tuple .{ ... } for " ++ @typeName(Actual));
                }
                const elements = std.meta.fields(Expected);
                try std.testing.expectEqual(elements.len, actual.len);
                inline for (elements, 0..) |element, index| {
                    expectValue(actual[index], @field(expected, element.name)) catch |err| {
                        std.debug.print("Mismatch at index {d}\n", .{index});
                        return err;
                    };
                }
            },
            else => @compileError("structural matching requires single-item pointers or slices"),
        },
        .optional => {
            if (Expected == @TypeOf(null)) {
                return std.testing.expectEqual(true, actual == null);
            }
            try std.testing.expectEqual(false, actual == null);
            try expectValue(actual.?, expected);
        },
        // Coerce literals such as .Add or 42 to the actual enum or integer type.
        else => try std.testing.expectEqualDeep(@as(Actual, expected), actual),
    }
}
