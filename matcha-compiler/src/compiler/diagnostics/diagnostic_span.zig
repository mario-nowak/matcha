pub const DiagnosticSpan = struct {
    line: usize,
    column: usize,
    byte_offset: usize,
    byte_len: usize,

    pub fn fromToken(token: anytype) DiagnosticSpan {
        return .{
            .line = token.line,
            .column = token.column,
            .byte_offset = token.offsetInSource,
            .byte_len = token.lenInSource,
        };
    }
};
