const lexing = @import("lexing");
const NodeId = @import("module.zig").NodeId;

pub const Pattern = struct {
    id: NodeId,
    kind: PatternKind,

    pub fn primaryToken(self: *const @This()) lexing.Token {
        return switch (self.kind) {
            .integer_literal => |integer_literal| integer_literal.minus_token orelse integer_literal.literal_token,
            .boolean_literal => |token| token,
            .string_literal => |token| token,
            .case => |case| case.qualifier_token orelse case.dot_token,
        };
    }
};

pub const PatternKind = union(enum) {
    integer_literal: IntegerLiteralPattern,
    boolean_literal: lexing.Token,
    string_literal: lexing.Token,
    case: CasePattern,
};

pub const IntegerLiteralPattern = struct {
    minus_token: ?lexing.Token,
    literal_token: lexing.Token,

    pub fn value(self: *const @This()) i64 {
        const literal_value = self.literal_token.kind.int_literal;
        return if (self.minus_token != null) -literal_value else literal_value;
    }
};

pub const CasePattern = struct {
    qualifier_token: ?lexing.Token,
    dot_token: lexing.Token,
    case_name_token: lexing.Token,
    binding: ?PayloadBinding,
};

pub const PayloadBinding = struct {
    id: NodeId,
    left_parenthesis: lexing.Token,
    name_token: lexing.Token,
    right_parenthesis: lexing.Token,
};
