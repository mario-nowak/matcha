const lexing = @import("lexing");
const NodeId = @import("module.zig").NodeId;

pub const Pattern = struct {
    id: NodeId,
    kind: PatternKind,
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
