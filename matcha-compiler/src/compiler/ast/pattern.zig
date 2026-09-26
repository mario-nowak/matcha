const lexing = @import("lexing");
const NodeId = @import("module.zig").NodeId;

pub const Pattern = struct {
    id: NodeId,
    kind: PatternKind,

    pub fn primaryToken(self: *const @This()) lexing.Token {
        return switch (self.kind) {
            .IntegerLiteral => |integer_literal| integer_literal.minus_token orelse integer_literal.literal_token,
            .BooleanLiteral => |token| token,
            .StringLiteral => |token| token,
            .Case => |case| case.qualifier_token orelse case.dot_token,
        };
    }
};

pub const PatternKind = union(enum) {
    IntegerLiteral: IntegerLiteralPattern,
    BooleanLiteral: lexing.Token,
    StringLiteral: lexing.Token,
    Case: CasePattern,
};

pub const IntegerLiteralPattern = struct {
    minus_token: ?lexing.Token,
    literal_token: lexing.Token,

    pub fn value(self: *const @This()) i64 {
        const literal_value = self.literal_token.kind.IntLiteral;
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
    left_parenthesis: lexing.Token,
    name_token: lexing.Token,
    right_parenthesis: lexing.Token,
};
