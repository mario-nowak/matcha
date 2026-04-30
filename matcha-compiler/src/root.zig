pub const lexing = @import("lexing");
pub const ast = @import("ast");
pub const type_expressions = @import("type_expressions");
pub const parsing = @import("parsing");
pub const typing = @import("typing");
pub const semantic_analysis = @import("semantic_analysis");
pub const emission = @import("emission");

test {
    _ = @import("tests.zig");
}
