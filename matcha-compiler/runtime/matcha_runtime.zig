const std = @import("std");

extern fn GC_init() void;
extern fn GC_malloc(size: usize) ?*anyopaque;
extern fn GC_malloc_atomic(size: usize) ?*anyopaque;
extern fn write(fd: c_int, buf: [*]const u8, count: usize) isize;

const stdout_fd: c_int = 1;
const stderr_fd: c_int = 2;

const MatchaString = extern struct {
    ptr: [*]const u8,
    len: usize,
};

const ArrayHeader = extern struct {
    length: i64,
    capacity: i64,
    data: ?*anyopaque,
};

fn writeTo(fd: c_int, bytes: []const u8) void {
    if (bytes.len == 0) {
        return;
    }

    _ = write(fd, bytes.ptr, bytes.len);
}

fn writeStdout(bytes: []const u8) void {
    writeTo(stdout_fd, bytes);
}

fn panic(message: []const u8) noreturn {
    writeTo(stderr_fd, message);
    writeTo(stderr_fd, "\n");
    std.process.exit(1);
}

fn isWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\n', '\r', '\t' => true,
        else => false,
    };
}

fn trimSlice(bytes: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = bytes.len;

    while (start < end and isWhitespace(bytes[start])) {
        start += 1;
    }
    while (end > start and isWhitespace(bytes[end - 1])) {
        end -= 1;
    }

    return bytes[start..end];
}

fn delimiterMatches(bytes: []const u8, delimiter: []const u8, index: usize) bool {
    return std.mem.eql(u8, bytes[index .. index + delimiter.len], delimiter);
}

fn countSplitParts(bytes: []const u8, delimiter: []const u8) usize {
    var parts: usize = 1;
    var index: usize = 0;

    while (index + delimiter.len <= bytes.len) {
        if (delimiterMatches(bytes, delimiter, index)) {
            parts += 1;
            index += delimiter.len;
        } else {
            index += 1;
        }
    }

    return parts;
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

export fn matcha_read_file(out: *MatchaString, path_ptr: [*]const u8, path_len: usize) void {
    const path = path_ptr[0..path_len];
    var file = std.fs.cwd().openFile(path, .{}) catch panic("panic: failed to open file");
    defer file.close();

    const file_size = file.getEndPos() catch panic("panic: failed to read file size");
    const allocation = matcha_allocate_atomic(@max(file_size, 1)) orelse panic("panic: out of memory");
    const bytes: [*]u8 = @ptrCast(allocation);
    const buffer = bytes[0..file_size];
    const bytes_read = file.readAll(buffer) catch panic("panic: failed to read file");

    out.* = .{
        .ptr = bytes,
        .len = bytes_read,
    };
}

export fn matcha_read_line(out: *MatchaString) void {
    const maybe_line = std.fs.File.stdin().deprecatedReader().readUntilDelimiterOrEofAlloc(
        std.heap.page_allocator,
        '\n',
        std.math.maxInt(usize),
    ) catch panic("panic: failed to read stdin");
    defer if (maybe_line) |line| std.heap.page_allocator.free(line);

    if (maybe_line) |line| {
        const trimmed_line = if (line.len > 0 and line[line.len - 1] == '\r')
            line[0 .. line.len - 1]
        else
            line;
        out.* = copyBytesToAtomic(trimmed_line);
    } else {
        out.* = copyBytesToAtomic("");
    }
}

fn copyBytesToAtomic(bytes: []const u8) MatchaString {
    const allocation = matcha_allocate_atomic(@max(bytes.len, 1)) orelse panic("panic: out of memory");
    const copied_ptr: [*]u8 = @ptrCast(allocation);
    if (bytes.len > 0) {
        @memcpy(copied_ptr[0..bytes.len], bytes);
    }

    return .{
        .ptr = copied_ptr,
        .len = bytes.len,
    };
}

var cached_program_arguments: ?*ArrayHeader = null;

fn buildArguments(argument_count_from_main: i32, argument_values_raw: *anyopaque) *ArrayHeader {
    const argument_values: [*]const [*:0]const u8 = @ptrCast(@alignCast(argument_values_raw));
    const argument_count: usize = if (argument_count_from_main <= 1) 0 else @intCast(argument_count_from_main - 1);

    const header_allocation = matcha_allocate(@sizeOf(ArrayHeader)) orelse panic("panic: out of memory");
    const header: *ArrayHeader = @ptrCast(@alignCast(header_allocation));

    const data_allocation = matcha_allocate(@max(argument_count, 1) * @sizeOf(MatchaString)) orelse panic("panic: out of memory");
    const data: [*]MatchaString = @ptrCast(@alignCast(data_allocation));

    var index: usize = 0;
    while (index < argument_count) : (index += 1) {
        const argument_c_string = argument_values[index + 1];
        const argument_slice = std.mem.span(argument_c_string);
        data[index] = copyBytesToAtomic(argument_slice);
    }

    header.* = .{
        .length = @intCast(argument_count),
        .capacity = @intCast(argument_count),
        .data = data_allocation,
    };

    return header;
}

fn cloneArguments(arguments_header: *ArrayHeader) *ArrayHeader {
    if (arguments_header.length < 0) {
        panic("panic: invalid arguments array length");
    }

    const argument_count: usize = @intCast(arguments_header.length);
    const cloned_header_allocation = matcha_allocate(@sizeOf(ArrayHeader)) orelse panic("panic: out of memory");
    const cloned_header: *ArrayHeader = @ptrCast(@alignCast(cloned_header_allocation));

    const cloned_data_allocation = matcha_allocate(@max(argument_count, 1) * @sizeOf(MatchaString)) orelse panic("panic: out of memory");
    const cloned_data: [*]MatchaString = @ptrCast(@alignCast(cloned_data_allocation));

    if (argument_count > 0) {
        const source_data_allocation = arguments_header.data orelse panic("panic: missing arguments data");
        const source_data: [*]const MatchaString = @ptrCast(@alignCast(source_data_allocation));
        @memcpy(cloned_data[0..argument_count], source_data[0..argument_count]);
    }

    cloned_header.* = .{
        .length = @intCast(argument_count),
        .capacity = @intCast(argument_count),
        .data = cloned_data_allocation,
    };

    return cloned_header;
}

export fn matcha_init_arguments(argument_count_from_main: i32, argument_values_raw: *anyopaque) void {
    cached_program_arguments = buildArguments(argument_count_from_main, argument_values_raw);
}

export fn matcha_get_arguments() *ArrayHeader {
    const arguments_header = cached_program_arguments orelse panic("panic: program arguments were not initialized");
    return cloneArguments(arguments_header);
}

export fn matcha_string_concatenate(
    out: *MatchaString,
    left_ptr: [*]const u8,
    left_len: usize,
    right_ptr: [*]const u8,
    right_len: usize,
) void {
    const result_len = left_len + right_len;
    const allocation = matcha_allocate_atomic(@max(result_len, 1)) orelse panic("panic: out of memory");
    const result_ptr: [*]u8 = @ptrCast(allocation);

    if (left_len > 0) {
        @memcpy(result_ptr[0..left_len], left_ptr[0..left_len]);
    }
    if (right_len > 0) {
        @memcpy(result_ptr[left_len .. left_len + right_len], right_ptr[0..right_len]);
    }

    out.* = .{
        .ptr = result_ptr,
        .len = result_len,
    };
}

export fn matcha_string_compare(
    left_ptr: [*]const u8,
    left_len: usize,
    right_ptr: [*]const u8,
    right_len: usize,
) bool {
    return std.mem.eql(u8, left_ptr[0..left_len], right_ptr[0..right_len]);
}

export fn matcha_string_trim(out: *MatchaString, ptr: [*]const u8, len: usize) void {
    const trimmed = trimSlice(ptr[0..len]);
    out.* = .{
        .ptr = trimmed.ptr,
        .len = trimmed.len,
    };
}

export fn matcha_string_split(
    ptr: [*]const u8,
    len: usize,
    delimiter_ptr: [*]const u8,
    delimiter_len: usize,
) *ArrayHeader {
    if (delimiter_len == 0) {
        panic("panic: cannot split by empty string");
    }

    const bytes = ptr[0..len];
    const delimiter = delimiter_ptr[0..delimiter_len];
    const parts = countSplitParts(bytes, delimiter);

    const header_allocation = matcha_allocate(@sizeOf(ArrayHeader)) orelse panic("panic: out of memory");
    const header: *ArrayHeader = @ptrCast(@alignCast(header_allocation));
    const data_allocation = matcha_allocate(parts * @sizeOf(MatchaString)) orelse panic("panic: out of memory");
    const data: [*]MatchaString = @ptrCast(@alignCast(data_allocation));

    header.* = .{
        .length = @intCast(parts),
        .capacity = @intCast(parts),
        .data = data_allocation,
    };

    var part_index: usize = 0;
    var part_start: usize = 0;
    var index: usize = 0;

    while (index + delimiter.len <= bytes.len) {
        if (delimiterMatches(bytes, delimiter, index)) {
            data[part_index] = .{
                .ptr = bytes.ptr + part_start,
                .len = index - part_start,
            };
            part_index += 1;
            index += delimiter.len;
            part_start = index;
        } else {
            index += 1;
        }
    }

    data[part_index] = .{
        .ptr = bytes.ptr + part_start,
        .len = bytes.len - part_start,
    };

    return header;
}

export fn matcha_string_to_int(ptr: [*]const u8, len: usize) i64 {
    return std.fmt.parseInt(i64, ptr[0..len], 10) catch panic("panic: failed to parse int");
}

export fn matcha_int_to_string(out: *MatchaString, value: i64) void {
    var buffer: [32]u8 = undefined;
    const rendered = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch panic("panic: failed to render int");
    out.* = copyBytesToAtomic(rendered);
}

export fn matcha_panic_index_out_of_bounds(line: usize, column: usize, index: i64, length: usize) noreturn {
    var buffer: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(
        &buffer,
        "panic: array index out of bounds at line {d}, column {d}: index {d}, length {d}",
        .{ line, column, index, length },
    ) catch unreachable;
    panic(formatted);
}
