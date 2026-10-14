---
author: claude
status: draft
---

# Shapes proposal

## AI Generated

A shape is a structural type: a set of fields without a name. `docs/goals.md` introduces two kinds.

```matcha
item greetExact(user: { name: string }) = "Hello, " + user.name;
item greetOpen(user: { name: string, .. }) = "Hello, " + user.name;
```

### Exact shapes

An exact shape `{ name: string }` is one concrete type. A value with more fields does not match it. Crossing that boundary is explicit, for example with spread: `.{ ..update }`.

### Open shapes

An open shape `{ name: string, .. }` accepts any structure that has at least these fields. The `..` works like a hidden type parameter with a "has these fields" constraint. So an open shape is an implicit generic (see the constraints proposal).

Each `..` is anonymous and separate. A function cannot say "both parameters have the same rest" or "I return the type I got". That needs a named type parameter.

### Lowering

The fields sit at different offsets in each concrete type. Options:

1. Monomorphization: one copy of the function per concrete type. This is the fastest code and matches generics. Start here.
2. A hidden offset argument: the caller passes the offset of each field (Ohori's 1995 scheme for record polymorphism). One copy of the function serves all types. A function that copies the value also needs its size.
3. Go's hybrid: one copy per memory layout class, plus a dictionary. Go chose this for compile speed.

### Future direction: mutation through open shapes

With value semantics, an `&` parameter can use an open shape:

```matcha
item rename(&user: { name: string, .. }, name: string): unit = {
    user.name = name;
};
```

This changes one field of any structure that has it, in place, without sharing. It means the same as row-polymorphic record update in Elm and PureScript, so its soundness is known. Unlike there, the row variable can stay anonymous, because nothing is returned. A first search found no language that combines open records with in-place borrowed mutation.

Rules:

1. Opaque structures never match an open shape on an `&` parameter. That would bypass the rule that only the type's own methods write its fields.
2. Field types match exactly for writes. TypeScript is unsound here, because it accepts a narrower field type where a wider one is written.
3. A field with a nested open shape can be written through, but not replaced as a whole, because the caller's concrete type of that field is unknown.

### Order

Open shapes are implicit generics, so they come after generics.
