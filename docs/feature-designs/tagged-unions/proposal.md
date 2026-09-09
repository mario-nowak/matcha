# Tagged Union Concept Document

This document is a scratchpad for tagged-union syntax and user-visible semantics.

## Prerequisite

The [equality proposal](../equality/proposal.md) must be implemented before tagged unions.

Tagged-union equality builds on the equality semantics of every possible payload type, including `unit` and reference-like types.

## Direction

A tagged union is a closed type expression containing named variants.

```matcha
item Direction = union {
    North,
    South,
    East,
    West,
};
```

`union { ... }` is a type expression. The `item` declaration binds that type expression to `Direction`.

## Variant declarations

A variant may declare its payload type after `:`. Commas separate variants.

```matcha
item WebEvent = union {
    PageLoad,
    PageUnload,
    KeyPress: string,
    Click: structure {
        x: int;
        y: int;
    },
    Paste: string,
};
```

A payload may use any valid type expression. This document only uses type expressions that are already part of the language.

Each variant semantically carries one payload. A variant without an explicit payload type uses `unit`.

```matcha
item Direction = union {
    North,
    South,
};
```

The semantic type model is equivalent to:

```matcha
item Direction = union {
    North: unit,
    South: unit,
};
```

Users normally omit the `unit` payload type.

## Construction

Contextual dot construction may be used when the expected union type is known.

```matcha
val direction: Direction = .North;
val event1: WebEvent = .PageLoad;
val event2: WebEvent = .KeyPress("Enter");
val event3: WebEvent = .Click(.{ x = 100, y = 200 });
```

Function arguments and return types may provide the expected union type.

```matcha
item handle(event: WebEvent): unit = unimplemented;
item defaultEvent(): WebEvent = .PageLoad;

handle(.KeyPress("Enter"));
```

Qualified construction may be used with or without an expected type.

```matcha
val event = WebEvent.KeyPress("Enter");
val direction = Direction.North;
```

Unqualified dot construction without an expected union type is invalid.

```matcha
val event = .KeyPress("Enter"); // Error: union type cannot be inferred
```

A bare unit variant constructs the variant with its `unit` payload.

```matcha
val direction: Direction = .North;
```

An explicit payload expression is also valid when that expression has type `unit`.

```matcha
item doNothing(): unit = {};

val direction: Direction = .North(doNothing());
```

An empty argument list does not provide a `unit` value.

```matcha
val direction: Direction = .North(); // Error: missing payload expression
```

A non-`unit` payload is invalid for a variant whose payload type is `unit`.

```matcha
val direction: Direction = .North(42); // Error: expected unit, found int
```

## Pattern matching

Parentheses contain a payload pattern.

```matcha
item processEvent(event: WebEvent): string = match event {
    .PageLoad => "Page loaded",
    .PageUnload => "Page unloaded",
    .KeyPress(key) => "Key pressed: " + key,
    .Click(point) => "Clicked at (" + point.x.toString() + ", " + point.y.toString() + ")",
    .Paste(text) => "Pasted: " + text,
};
```

A bare tag pattern matches the variant and ignores its payload.

```matcha
item eventName(event: WebEvent): string = match event {
    .PageLoad => "PageLoad",
    .PageUnload => "PageUnload",
    .KeyPress => "KeyPress",
    .Click => "Click",
    .Paste => "Paste",
};
```

Do not use an explicit wildcard to ignore the entire payload.

```matcha
.KeyPress => "KeyPress"
```

Adding a payload to a variant does not invalidate an existing bare tag pattern. The pattern continues to match that variant and ignore its payload.

A normal `match` over a tagged union must be exhaustive.

### Catch-all matching

An `else` arm matches every variant not handled by an earlier arm.

```matcha
item eventName(event: WebEvent): string = match event {
    .KeyPress(key) => "KeyPress: " + key,
    else => "Other event",
};
```

The `else` arm makes the match exhaustive.

## Equality

Two values of the same tagged-union type may be compared with `==` or `!=` when every variant payload type supports equality.

Equality first compares the active tags.

- Different tags compare unequal.
- Equal tags compare their payloads with the payload type's ordinary `==` operator.
- Unit payloads always compare equal.
- `!=` is the logical negation of `==`.

```matcha
val first: Direction = .North;
val second: Direction = .North;
val third: Direction = .South;
val sameTag = first == second; // true
val differentTag = first == third; // false
```

Payload values participate in equality.

```matcha
val first: WebEvent = .KeyPress("Enter");
val second: WebEvent = .KeyPress("Enter");
val third: WebEvent = .KeyPress("Escape");
val samePayload = first == second; // true
val differentPayload = first == third; // false
val differentTag = first == .PageLoad; // false
```

Contextual dot construction may obtain its expected union type from the other equality operand.

```matcha
val isEnter = event == .KeyPress("Enter");
val isNorth = direction == .North;
```

A bare variant with a non-`unit` payload remains invalid in value position. Bare variants ignore payloads only in pattern position.

```matcha
event == .KeyPress // Error: missing string payload
```

Different tagged-union types cannot be compared, even when their variants have identical names and payload types.

A tagged union does not support equality when any variant payload type does not support equality. For example, a tagged union containing a function payload cannot use `==` or `!=`.

Structure and array payloads use the reference-identity semantics defined in the equality proposal. Tagged-union equality does not recursively inspect those values.

## Syntax selected for this draft

Variant declarations use `:` for the payload type and `,` between variants.

```matcha
item Result = union {
    Ok: int,
    Error: string,
};
```

Construction and payload patterns use parentheses because the parentheses visually contain the payload within the tag.

```matcha
val result: Result = .Ok(42);

val message = match result {
    .Ok(value) => value.toString(),
    .Error(message) => message,
};
```

These parentheses are not redundant control-flow parentheses. They express the relationship between a tag and its payload.

## Alternatives not selected

### Parenthesized payload type declarations

```matcha
item Result = union {
    Ok(int);
    Error(string);
};
```

Not selected. Colon follows Matcha's existing type-annotation syntax. Commas fit a list of alternatives better than semicolons.

### Colon payload patterns

```matcha
.Ok: value => value.toString()
```

Not selected. Colon does not group the payload strongly enough within the tag.

### Capture bars attached to the tag

```matcha
.Ok|value| => value.toString()
```

Not selected. Bars add punctuation and provide weaker payload grouping than parentheses.

### Zig-style capture clauses

```matcha
.Ok => |value| value.toString()
```

Not selected. The capture is visually separated from the tag whose payload it receives.

### Explicit wildcard for an ignored payload

```matcha
.Ok(_) => "Ok"
```

Not selected. Omitting the parentheses already expresses that the payload is ignored.
