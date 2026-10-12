# Value semantics proposal (draft)

Decided on 2026-10-09. Work starts after the module system, which is now done. Matcha moves from reference semantics to value semantics, because signatures and `var` then make every mutation visible ("nothing happens silently").

## Ideas

- `val` never changes, deeply. `var` can change. Parts of a place (fields, elements, `for` and `match` bindings) inherit the mutability of the place.
- Mutability belongs to the place, not to the type. Reference mutability belongs to the type: `*T` is read-only, `*var T` can change. `*var T` coerces to `*T`. There is no `*val`.
- Parameters are immutable values. A function that changes an argument takes `x: *var T`. `x.method()` passes `*var` implicitly when `x` is a `var` place.
- `*T` and `*var T` can be stored, but only as references to whole bindings, never into array elements or union payloads. The Boehm GC keeps escaped bindings alive.
- Inside a `match` arm or a `for` loop, the subject can only change through its bindings.
- Arrays: one growable `[]T` with value semantics, like Swift's `Array`. No separate slice or `ArrayList` type, so no stale views. Copy on write through a shared flag is an optional later optimization.
- Syntax: prefix `[]T`, consistent with `*T` and a future `?T`. Examples: `[]*var User`, `*[]User`.
- `val b = a` may reuse the storage of `a`, and a move on last use is an invisible optimization. Semantically, `b` is an independent value.
- No migration guardrails. Existing code gets ported in one step.

## Known cost

Value semantics has its own silent mistake: you expect sharing but get a copy. `*var T` is the explicit way to share.

## To do at the switch

- Revise `docs/feature-designs/equality/proposal.md`. Structure and array equality is reference identity there, and must become value equality.
- Checkpoint: port one non-toy program before committing to the details. `examples/todo-api-round-trip/` is a candidate. Paper ports of smaller programs exist in the git stash entry "Add programs to decide value semantics".

## Effect on C interop

Value semantics makes C interop easier (see `extern-items/proposal.md`): a structure is its bytes, so it can match a C struct and be passed by value. Arrays of structures become contiguous. `*T` and `*var T` map to `const T*` and `T*`.
