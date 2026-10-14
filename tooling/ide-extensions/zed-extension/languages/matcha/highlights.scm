(comment) @comment
(string) @string
(escape_sequence) @string.escape
(integer) @number
(boolean) @boolean
(keyword) @keyword
(operator) @operator

["(" ")" "{" "}" "[" "]"] @punctuation.bracket

((identifier) @keyword
  (#any-of? @keyword "item" "export" "import"))

((identifier) @type.builtin
  (#any-of? @type.builtin "int" "boolean" "string" "unit"))

((identifier) @variable.special
  (#eq? @variable.special "self"))

((identifier) @type
  (#match? @type "^[A-Z]"))

((identifier) @function
  .
  (parenthesized_group)
  (#match? @function "^[a-z_]"))

((identifier) @_item
  .
  (identifier) @function
  (#eq? @_item "item")
  (#match? @function "^[a-z_]"))

((keyword) @_binding
  .
  (identifier) @variable
  (#any-of? @_binding "val" "var"))
