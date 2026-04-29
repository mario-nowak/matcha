const std = @import("std");

extern fn GC_init() void;
extern fn GC_malloc(size: usize) ?*anyopaque;
extern fn GC_malloc_atomic(size: usize) ?*anyopaque;
extern fn write(fd: c_int, buf: [*]const u8, count: usize) isize;

const stdout_fd: c_int = 1;

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

export fn matcha_print_int(value: i64) void {
    var buffer: [32]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{d}\n", .{value}) catch unreachable;
    writeStdout(formatted);
}

export fn matcha_print_string(ptr: [*]const u8, len: usize) void {
    writeStdout(ptr[0..len]);
    writeStdout("\n");
}
