const e2e = @import("helpers.zig");

test "readLine reads a line from stdin" {
    const source =
        \\printString(readLine());
    ;
    const stdin = "hello from stdin\n";

    var result = try e2e.runSourceWith("io_read_line.mt", source, .{ .stdin = stdin });
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "hello from stdin\n");
}

test "getArguments forwards command-line arguments" {
    const source =
        \\val args = getArguments();
        \\printInt(args.length);
        \\if args.length > 0 {
        \\    printString(args[0]);
        \\}
        \\if args.length > 1 {
        \\    printString(args[1]);
        \\}
    ;
    const program_arguments = [_][]const u8{ "alpha", "beta" };

    var result = try e2e.runSourceWith("io_get_arguments.mt", source, .{ .program_arguments = &program_arguments });
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "2\nalpha\nbeta\n");
}

test "readFile reads file contents from disk" {
    const source =
        \\val content = readFile("tests/e2e/programs/io/read_file_input.txt");
        \\printString(content.trim());
    ;

    var result = try e2e.runSource("io_read_file.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "matcha file input\n");
}

test "startProcess returns the stdout of the started process" {
    const source =
        \\printString(startProcess("echo", ["hello", "matcha"]).trim());
    ;

    var result = try e2e.runSource("io_start_process.mt", source);
    defer result.deinit();

    try e2e.expectSuccessOutput(&result, "hello matcha\n");
}

test "startProcess panics with the exit status and stderr when the process exits with a non-zero status" {
    const source =
        \\printString(startProcess("sh", ["-c", "echo oops >&2; exit 3"]));
    ;

    var result = try e2e.runSource("io_start_process_failure.mt", source);
    defer result.deinit();

    try e2e.expectRuntimeError(&result, "oops\nruntime error: process exited with status 3\n");
}
