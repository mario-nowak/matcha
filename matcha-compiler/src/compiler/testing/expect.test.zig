const std = @import("std");
const expect = @import("testing").expect;

test "Expectation > toMatchMap: matches exact entries regardless of order" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();
    try actual.put(1, 10);
    try actual.put(2, 20);

    const result = expect(actual).toMatchMap(.{
        .{ .key = 2, .value = 20 },
        .{ .key = 1, .value = 10 },
    });

    try result;
}

test "Expectation > toMatchMap: matches an empty map" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();

    const result = expect(actual).toMatchMap(.{});

    try result;
}

test "Expectation > toMatchMap: rejects additional entries" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();
    try actual.put(1, 10);
    try actual.put(2, 20);

    const result = expect(actual).toMatchMap(.{
        .{ .key = 1, .value = 10 },
    });

    try expect(result).toBeError(error.TestExpectedEqual);
}

test "Expectation > toMatchMap: rejects a missing key" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();
    try actual.put(1, 10);

    const result = expect(actual).toMatchMap(.{
        .{ .key = 2, .value = 10 },
    });

    try expect(result).toBeError(error.TestExpectedEqual);
}

test "Expectation > toMatchMap: rejects a different value" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();
    try actual.put(1, 10);

    const result = expect(actual).toMatchMap(.{
        .{ .key = 1, .value = 20 },
    });

    try expect(result).toBeError(error.TestExpectedEqual);
}

test "Expectation > toMatchMap: rejects duplicate expected keys" {
    var actual = std.AutoHashMap(u32, u32).init(std.testing.allocator);
    defer actual.deinit();
    try actual.put(1, 10);
    try actual.put(2, 10);

    const result = expect(actual).toMatchMap(.{
        .{ .key = 1, .value = 10 },
        .{ .key = 1, .value = 10 },
    });

    try expect(result).toBeError(error.TestExpectedEqual);
}

test "Expectation > toBeError: accepts the expected error" {
    const actual: error{DiagnosticsEmitted}!void = error.DiagnosticsEmitted;

    const result = expect(actual).toBeError(error.DiagnosticsEmitted);

    try result;
}

test "Expectation > toBeError: rejects a different error" {
    const actual: error{OutOfMemory}!void = error.OutOfMemory;

    const result = expect(actual).toBeError(error.DiagnosticsEmitted);

    try std.testing.expectError(error.TestUnexpectedError, result);
}

test "Expectation > toBeError: rejects a successful value" {
    const actual: error{DiagnosticsEmitted}!u32 = 42;

    const result = expect(actual).toBeError(error.DiagnosticsEmitted);

    try std.testing.expectError(error.TestExpectedError, result);
}

test "Expectation > toMatch: compares nested fields and ignores omitted fields" {
    const Mode = enum { Read, Write };
    const actual = .{ .name = @as([]const u8, "example"), .options = .{ .mode = Mode.Read, .enabled = true }, .id = 42 };
    const expected = .{ .name = "example", .options = .{ .mode = .Read } };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: rejects different string contents" {
    const actual: []const u8 = "first";
    const expected = "second";

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: follows pointers to compare their values" {
    const value = .{ .count = @as(u32, 42) };
    const actual = &value;
    const expected = .{ .count = 42 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: matches payload-free union cases" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .Ready;
    const expected = .Ready;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: compares union payloads" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .{ .Count = 42 };
    const expected = .{ .Count = 42 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: rejects a different active union case" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .Ready;
    const expected = .{ .Count = 42 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: rejects different union payloads" {
    const State = union(enum) { Ready, Count: u32 };
    const actual: State = .{ .Count = 42 };
    const expected = .{ .Count = 43 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: matches an empty slice with an empty tuple" {
    const actual: []const u32 = &.{};
    const expected = .{};

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: compares all slice elements against tuple elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 1, 2 };

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: rejects additional actual slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{1};

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: rejects missing actual slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 1, 2, 3 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: rejects reordered slice elements" {
    const actual: []const u32 = &.{ 1, 2 };
    const expected = .{ 2, 1 };

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: matches absent optional values" {
    const actual: ?u32 = null;
    const expected = null;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: compares present optional values against payload expectations" {
    const actual: ?u32 = 42;
    const expected = 42;

    const result = expect(actual).toMatch(expected);

    try result;
}

test "Expectation > toMatch: rejects an absent optional value when a payload is expected" {
    const actual: ?u32 = null;
    const expected = 42;

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "Expectation > toMatch: rejects a present optional value when null is expected" {
    const actual: ?u32 = 42;
    const expected = null;

    const result = expect(actual).toMatch(expected);

    try std.testing.expectError(error.TestExpectedEqual, result);
}
