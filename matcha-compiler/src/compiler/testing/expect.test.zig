const std = @import("std");
const expect = @import("testing").expect;

test "matcher compares nested fields and ignores omitted fields" {
    const Mode = enum { Read, Write };
    const actual = .{ .name = @as([]const u8, "example"), .options = .{ .mode = Mode.Read, .enabled = true }, .id = 42 };
    const expected = .{ .name = "example", .options = .{ .mode = .Read } };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher rejects different string contents" {
    const actual: []const u8 = "first";
    const expected = "second";

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher follows pointers to compare their values" {
    const value = .{ .count = @as(u32, 42) };
    const actual = &value;
    const expected = .{ .count = 42 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher matches payload-free union cases" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .Ready;
    const expected = .Ready;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher compares union payloads" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .{ .Count = 42 };
    const expected = .{ .Count = 42 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher rejects a different active union case before reading its payload" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .Ready;
    const expected = .{ .Count = 42 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher rejects different union payloads" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .{ .Count = 42 };
    const expected = .{ .Count = 43 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher matches an empty slice with an empty tuple" {
    const actual: []const u32 = &.{};
    const expected = .{};

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher compares all slice elements against tuple elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 1, 2 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher rejects additional actual slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{1};

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher rejects missing actual slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 1, 2, 3 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher rejects reordered slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 2, 1 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher matches absent optional values" {
    const actual: ?u32 = null;
    const expected = null;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher compares present optional values against payload expectations" {
    const actual: ?u32 = 42;
    const expected = 42;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "matcher rejects an absent optional value when a payload is expected" {
    const actual: ?u32 = null;
    const expected = 42;

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "matcher rejects a present optional value when null is expected" {
    const actual: ?u32 = 42;
    const expected = null;

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}
