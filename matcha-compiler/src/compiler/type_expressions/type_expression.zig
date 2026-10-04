const lexing = @import("lexing");

pub const TypeExpression = union(enum) {
    named: NamedTypeExpression,
    array: ArrayTypeExpression,
};

pub const NamedTypeExpression = struct {
    name_token: lexing.Token,
};

pub const ArrayTypeExpression = struct {
    element_type: *TypeExpression,
    left_bracket_token: lexing.Token,
    right_bracket_token: lexing.Token,
};
