const std = @import("std");

const builtins_import_path = "builtin";

pub const ImportPathResolution = union(enum) {
    builtins,
    /// The path of the imported file, relative to the same directory as the importing module's path.
    module_path: []const u8,
    missing_extension,
};

/// Decides what an import path names without reading any file, so the module loader and the test fixtures follow one rule.
pub fn resolveImportPath(
    arena: std.mem.Allocator,
    importing_module_path: []const u8,
    import_path: []const u8,
) !ImportPathResolution {
    if (std.mem.eql(u8, import_path, builtins_import_path)) {
        return .builtins;
    }
    if (!std.mem.endsWith(u8, import_path, ".mt")) {
        return .missing_extension;
    }
    // The joined path stays relative, so diagnostics stay readable.
    return .{ .module_path = try std.fs.path.resolve(
        arena,
        &.{ std.fs.path.dirname(importing_module_path) orelse "", import_path },
    ) };
}
