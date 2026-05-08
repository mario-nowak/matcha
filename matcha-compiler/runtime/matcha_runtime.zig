const std = @import("std");

extern fn GC_init() void;
extern fn GC_malloc(size: usize) ?*anyopaque;
extern fn GC_malloc_atomic(size: usize) ?*anyopaque;
extern fn write(fd: c_int, buf: [*]const u8, count: usize) isize;

const stdout_fd: c_int = 1;

const ArrayHeader = extern struct {
    length: i64,
    capacity: i64,
    data: ?*anyopaque,
};

fn writeStdout(bytes: []const u8) void {
    if (bytes.len == 0) {
        return;
    }

    _ = write(stdout_fd, bytes.ptr, bytes.len);
}

export fn matcha_initiate_garbage_collector() void {
    GC_init();
}

export fn matcha_allocate(size: usize) ?*anyopaque {
    return GC_malloc(size);
}

export fn matcha_allocate_atomic(size: usize) ?*anyopaque {
    return GC_malloc_atomic(size);
}

export fn matcha_array_append_slot(header: *ArrayHeader, element_size: usize) ?*anyopaque {
    const length: usize = @intCast(header.length);
    const capacity: usize = @intCast(header.capacity);

    if (length == capacity) {
        const new_capacity = if (capacity == 0) @as(usize, 1) else capacity * 2;
        const new_data = GC_malloc(new_capacity * element_size) orelse return null;

        if (length > 0) {
            const source_bytes: [*]const u8 = @ptrCast(header.data.?);
            const destination_bytes: [*]u8 = @ptrCast(new_data);
            @memcpy(
                destination_bytes[0 .. length * element_size],
                source_bytes[0 .. length * element_size],
            );
        }

        header.data = new_data;
        header.capacity = @intCast(new_capacity);
    }

    const data_bytes: [*]u8 = @ptrCast(header.data.?);
    const slot: [*]u8 = data_bytes + (length * element_size);
    header.length += 1;
    return @ptrCast(slot);
}

export fn matcha_print_int(value: i64) void {
    var buffer: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{d}\n", .{value}) catch unreachable;
    writeStdout(formatted);
}

export fn matcha_print_string(ptr: [*]const u8, len: usize) void {
    writeStdout(ptr[0..len]);
    writeStdout("\n");
}

export fn matcha_panic_index_out_of_bounds(line: usize, column: usize, index: i64, length: usize) noreturn {
    var buffer: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(
        &buffer,
        "panic: array index out of bounds at line {d}, column {d}: index {d}, length {d}\n",
        .{ line, column, index, length },
    ) catch unreachable;
    writeStdout(formatted);
    std.process.exit(1);
}
