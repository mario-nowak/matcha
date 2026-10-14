/**
 * Token-level grammar: it knows Matcha's tokens and bracket nesting, but not its syntax.
 * Highlight queries get context from neighboring tokens, so syntax changes rarely need grammar changes.
 */
module.exports = grammar({
  name: 'matcha',

  extras: $ => [/\s/, $.comment],

  word: $ => $.identifier,

  rules: {
    source_file: $ => repeat($._token),

    _token: $ => choice(
      $.parenthesized_group,
      $.braced_group,
      $.bracketed_group,
      $.keyword,
      $.boolean,
      $.identifier,
      $.integer,
      $.string,
      $.operator,
    ),

    parenthesized_group: $ => seq('(', repeat($._token), ')'),
    braced_group: $ => seq('{', repeat($._token), '}'),
    bracketed_group: $ => seq('[', repeat($._token), ']'),

    // `item`, `export` and `import` are contextual, so the compiler lexes them as identifiers.
    keyword: _ => choice(
      'val', 'var', 'if', 'else', 'match', 'not', 'and', 'or', 'loop', 'leave',
      'continue', 'while', 'for', 'in', 'return', 'structure', 'union',
    ),

    boolean: _ => choice('true', 'false'),

    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    integer: _ => /[0-9]+/,

    string: $ => seq(
      '"',
      repeat(choice($.string_content, $.escape_sequence)),
      '"',
    ),
    // Precedence keeps `//` inside a string from starting a comment.
    string_content: _ => token.immediate(prec(1, /[^"\\]+/)),
    escape_sequence: _ => token.immediate(/\\[nrt"\\]/),

    operator: _ => choice(
      '=>', '==', '!=', '<=', '>=', '+=', '-=', '*=',
      '=', '+', '-', '*', '/', '<', '>', '.', ':', ';', ',',
    ),

    comment: _ => token(seq('//', /.*/)),
  },
});
