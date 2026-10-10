const ModuleId = @import("source_registry.zig").ModuleId;

pub const DiagnosticSpan = struct {
    module_id: ModuleId,
    line: usize,
    column: usize,
    byte_offset: usize,
    byte_len: usize,

    pub fn fromToken(token: anytype) DiagnosticSpan {
        return .{
            .module_id = token.module_id,
            .line = token.line,
            .column = token.column,
            .byte_offset = token.offset_in_source,
            .byte_len = token.length_in_source,
        };
    }
};
