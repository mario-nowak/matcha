const std = @import("std");
const e2e = @import("helpers.zig");

pub const imports = struct {
    test "reports an import of a module that does not exist" {
        var result = try e2e.runFile("tests/e2e/programs/modules/missing_import.mt");
        defer result.deinit();

        try e2e.expectCompileDiagnostic(&result, "cannot find module 'missing.mt'");
    }

    test "reports a syntax error in an imported module at the path of that module" {
        var result = try e2e.runFile("tests/e2e/programs/modules/import_with_syntax_error.mt");
        defer result.deinit();

        try e2e.expectCompileDiagnostic(&result, " --> tests/e2e/programs/modules/broken_geometry.mt:");
    }

    test "runs a program that uses the exported items of an imported module" {
        var result = try e2e.runFile("tests/e2e/programs/modules/shapes/main.mt");
        defer result.deinit();

        try e2e.expectSuccessOutput(&result, "dot with length 20\nempty\nempty / empty\nabab\n");
    }
};
