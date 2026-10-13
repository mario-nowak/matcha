---
author: @mario-nowak
llm: claude-opus-5.5
---

# Value semantics decision record

This record lists the decisions behind [proposal.md](proposal.md), with the alternatives that were considered and the reasons for each choice. Most decisions come from a design discussion on 2026-10-13. Each entry has the decision, the alternatives, and the reasons.

## D1. Value semantics instead of reference semantics

Decided on 2026-10-09.

- Decision: Matcha moves from reference semantics to value semantics.
- Alternative: keep reference semantics, where every structure, union, and array is a shared heap object.
- Reasons: with value semantics, signatures and bindings show every mutation ("nothing happens silently"). Paper ports of small programs found no showstopper.

## D2. No stored references

- Decision: references exist only for the duration of a call. Nothing can store a reference to a value.
- Alternative: the first draft allowed `*T` (read-only) and `*var T` (changeable) to be stored, but only as references to whole bindings, never into array elements or union payloads.
- Reasons:
  1. The rule "only whole bindings" cannot be checked. A method call needs references into parts, for example `tasks[0].complete()`. A callee that takes `x: *Task` cannot tell whether the caller passed `&design` or `&tasks[0]`. If the callee stores `x`, a reference into an element escapes. Closing this hole needs a second reference type or escape analysis.
  2. A stored `*var T` brings back shared mutable aliasing. The rule "inside a loop, the subject changes only through the binding" becomes unenforceable, because another path can change the subject. Parameters stop being immutable, because a stored alias can change the caller's value during the call.
  3. `val` is not deep through a stored reference: a `val` holding a `*T` sees changes made elsewhere.
- The task-dependencies paper port already showed that IDs into a container work without stored references.

## D3. How to handle references into array elements and union payloads

The question was whether stored references into parts could be made safe. Today this is safe, because every structure is its own heap object, and a reference points to an object, not to a slot. With inline storage, a reference into a part points into the container's storage, and that storage can move (array growth) or change type (union variant change).

Alternatives considered:

1. Go's model: allow `&s[0]`. The GC keeps the old buffer alive, so nothing crashes, but after a reallocating `append` the reference writes to the old buffer and the array never sees it. Go forbids `&m[k]` for maps for this reason, but allows it for slices. Go has no inline union payloads: interface payloads are boxed and unaddressable. Rejected: silent stale writes are the bug class value semantics should remove, and inline union payloads would allow real type confusion.
2. Box every element, as today. Element references never go stale. Rejected: one allocation per element, deep copies of arrays, and no contiguous layout for C interop.
3. Path references: a reference stores the binding and the index, and indexes again on every access. Rejected: after a remove or insert it silently refers to a different element.
4. Checked references, like Vale's generational references: a reference stores a generation number, and every access compares it. A stale access panics instead of writing silently. Rejected for now: extra memory and a check per access, and staleness is still only found at runtime. It stays possible later, because it only lifts a restriction.
5. A borrow checker, like Rust, or Valen's group borrowing. Rejected: `docs/goals.md` excludes ownership and borrow-checking machinery.
6. Swift's model: references into parts exist only during a call (`inout`), and sharing needs a `class`. This is close to the chosen model.
7. Hylo's mutable value semantics: no first-class references at all, only parameter conventions. Chosen as the base, because every complication above comes from stored references.

## D4. Sharing through identity structures

- Decision: `structure` is a value, and `identity structure` is a shared object. Identity structures are the only way to store a reference.
- Alternatives:
  1. The original Matcha draft: structures are references by default, and `inline structure` opts into value semantics. Rejected: sharing would be the default, and value semantics the exception.
  2. Stored references (D2). Rejected.
  3. A generic box type, like `Shared<T>`. Rejected for now: Matcha has no generics, and a box hides sharing in the use, not in the type declaration.
- Reasons: a pure value model is awkward for long-lived services with state. In the Pickware business platform, `CartService` holds a price cache and is injected into other services. As a value, each holder would get its own copy, and the cache would silently stop working. `identity` makes sharing visible in the type declaration. Precedent: Swift `class`, C# `class`, and Java Valhalla, which uses the same word "identity".

## D5. Mutability of identity structure fields

- Decision: a field of an identity structure is fixed after construction, unless it is declared `var`. `var` fields exist only in identity structures.
- Alternatives:
  1. The binding decides, as for values. Rejected: many bindings refer to one object, so a `val` and a `var` binding could disagree about the same object.
  2. All fields are always changeable, as in Go. Rejected: shared objects lose read-only fields.
  3. `var` fields in value structures too. Rejected: a `var` field in a `val` binding would break deep `val`.
  4. Fields that stay fixed inside a `var` value, like Swift's `let` properties in a struct. Not adopted: `opaque` covers the cases where a field needs protection.
- Reasons: an identity object is "a bundle of bindings". Each field is its own binding and declares its own mutability. Precedent: Kotlin `val`/`var` properties, Swift class `let`/`var` properties.

## D6. The parameter mode for changing an argument

- Decision: the parameter is marked with `&` before its name (`&line: Line`), and the call site passes `&x`. Receivers use `&self: T`.
- Alternatives, in the order they came up:
  1. `x: *var T` from the first draft. Rejected with D2.
  2. A `mut` keyword (`x: mut T`, call `f(mut x)`). Rejected: the keyword reads heavy. A `var` keyword in this position was also rejected: Swift had `var` parameters that meant a local copy, people confused them with `inout`, and Swift 3 removed them (SE-0003).
  3. `x: *T` in the type, with `&x` at the call site. This is the Go and Zig spelling. Rejected: `*T` would be a type that is legal only on parameters, and Go and Zig users would try `Task*[]` or a `*Task` field.
  4. `*line: Line`. Rejected: it reads strangely.
  5. `ref line: Line`, as in C#. Rejected: another keyword.
  6. `line!: Line` with `f(path!)`, the Ruby convention for mutation. Rejected: with postfix optionals, `path!` reads like TypeScript's non-null assertion or Swift's force-unwrap.
  7. A suffix marker, `self&` or `self*`. Rejected: the call site still wants a prefix `&path`, so the declaration and the call would differ. A suffix `&` at the call site would also conflict with a future binary `&`. Suffix markers create punctuation clusters (`&,` and `&:`), and they are harder to scan than a marker at the start of each parameter.
- Reasons for `&line`:
  1. `&` is not type syntax, so no rule like "only legal on parameters" is necessary.
  2. The declaration and the call site use the same marker.
  3. Go users read `&x` as "pass my variable so it can change".
  4. Precedent for a marker before the name: Mojo's `mut x: T`, C#'s `ref x`.
- Known cost: Rust users may read `&self` as read-only, because Rust uses `&mut self` for the changeable form.

## D7. No read-only reference parameters

- Decision: there is no read-only reference mode. A normal parameter is an immutable value, and the compiler chooses to pass it by value or by pointer.
- Alternative: Zig's choice between `T` and `*const T`.
- Reasons: nothing can change a parameter during the call, so passing by value and passing by read-only reference cannot be told apart. In Zig, `*const T` is a performance choice that can also leak: another alias can change the value during the call. The call site still shows the part that matters: whether the call can change the argument (`&x`). Zig's `&x` shows "pointer", not "changeable".

## D8. Array and optional syntax

- Decision: arrays stay postfix (`T[]`), as Matcha has them today. Optionals are planned as postfix `T?`. All type modifiers sit on the right.
- Alternative: prefix `[]T`, from the first draft, chosen so that `[]*Task` was unambiguous.
- Reasons:
  1. With D2 and D6, no reference appears inside a type, so the `[]*Task` argument is gone.
  2. Mixing sides is the only bad option: with a prefix `?` and a postfix `[]`, `?Task[]` is ambiguous.
  3. `User?` is the mainstream spelling (Swift, Kotlin, C#, Dart, TypeScript property types). It reads like the question it is, and it matches optional chaining like `user?.name`.
  4. Cost: nested types read right to left. `User?[]` is an array of optional users, and `User[]?` is an optional array. Nested optionals and arrays are rare in service code.

## D9. Binding keywords

- Decision: keep `val` and `var`. The compiler warns when a `var` never changes.
- Alternatives:
  1. `val` and `mut`. Rejected: `mut first` reads badly, and `mut` alone as a declaration keyword is unusual.
  2. `let` and `var`, as in Swift. Considered, because the first letters differ more than in `val` and `var`. Not adopted, because the compiler catches every mix-up.
- Reasons: a `val` that changes is a compile error, and a `var` that never changes is a warning. So the one-letter difference cannot hide a bug.

## D10. Copy costs

- Decision: copies are implicit. Arrays use copy-on-write. Diagnostics and an optional compiler flag show copy costs.
- Alternatives:
  1. Forbid copies of expensive values entirely. Rejected: not practical.
  2. Moves with explicit copies, as in Rust and Hylo. Assignment moves values that contain arrays, the source becomes unusable, and a copy must be explicit, for example `.copy()` or spread (`[..first]`, `User { ..user }`). Explicit copies would also catch the trap "expected sharing, got a copy". Rejected: Go users, the target audience, would see "used after move" errors on plain assignments as complexity. A function that stores a parameter would need a third parameter mode that takes ownership, like Swift's `consuming` or Hylo's `sink`. The compiler would need move tracking across control flow. Moves can still come later as an opt-in. Removing them after shipping would break code.
- Reasons: Go users do not expect copy costs to be visible: Go copies structures and fixed-size arrays silently. Copy-on-write makes most copies free, and only real divergence pays. The wish for visible costs is served by a diagnostic and a compiler flag, not by syntax in normal code.
- The Boehm GC has no reference counts, so copy-on-write uses a shared flag on the buffer. This can cause one unnecessary copy.

## D11. Parameters never copy or move

- Decision: passing a value to a normal parameter is a borrow. The caller keeps its value. Storing a parameter copies it, cheaply through copy-on-write.
- Reason: with moves (D10), storing a parameter would need an ownership-taking parameter mode. Without moves, the rule stays simple.

## D12. Opaque structures stay

- Decision: `opaque` stays, independent of value and identity. All four combinations are valid.
- Alternative: drop opaque structures, because their point (private fields and a required constructor) seemed tied to reference semantics.
- Reasons: invariants are about who can construct and write, not about sharing. `item UserId = opaque string;` is already an opaque value. Value semantics makes invariants stronger, because no other holder can change a value. Precedent: Swift structs with private fields and an `init`, Rust structs with private fields, Haskell smart constructors.

## D13. Field visibility and writes in opaque structures

- Decision: fields are readable from outside by default. `private` hides a field. Only the type's own methods write fields. `private` is only allowed in opaque structures.
- Alternatives:
  1. Private by default with a `public` modifier, as in the `Email` example in `docs/goals.md`. Rejected: user preference for public by default and spelling out `private`.
  2. Public fields writable from outside. Rejected: `var range = DateRange(10, 20); range.start = 30;` would bypass the constructor's invariant, because `var` gives write access to all parts of a copy.
  3. `private` in plain structures. Rejected: outside code constructs a plain structure with a literal, and the literal must set every field.

## D14. Construction of opaque structures

- Decision: only the constructor creates an opaque structure, everywhere, also inside the type. Literals and spread are errors. The type's own methods may write fields through `&self`, and each changing method keeps the invariant, as in a TypeScript class with private fields. Copies are not creations.
- Alternatives:
  1. The type is the trust boundary, as in Rust, Swift, and Kotlin: inside the type, literals, spread, and field writes are all allowed. Rejected: constructions would be scattered across the type.
  2. Strict: only the constructor sets fields, and changing methods replace the whole value with `self = .(...)`. Every value then comes from the constructor, and validation lives in one place. Rejected as too restrictive. It would also need a private constructor for internal state.
  3. Forbid spread inside the type, but allow field writes. Rejected: `.{ ..self, end = end }` has the same power as `var copy = self; copy.end = end;`, so this would look strict without being strict.
  4. Declared invariants, as in Eiffel, D, and Ada: the type declares one check, and the compiler runs it after every construction, including spread from outside. Deferred: it moves invariant failures to runtime at every construction site, and it is a bigger feature. Revisit if `withX` methods become boilerplate.

## D15. Mutable `for` and `match` bindings

- Decision: a `for` or `match` binding is the element or payload itself, and it inherits the mutability of the subject. Inside the loop or arm, the subject changes only through the binding.
- Alternative: Swift's model, where the binding is a copy, and changing elements needs an index loop or copy-and-reassign.
- Reasons: it removes a daily annoyance from Swift and Go. Go's `for _, u := range users { u.Done = true }` silently changes a copy.

## D16. Equality

- Decision: values compare contents, and identity structures compare identity. No conformance is needed.
- Alternatives: the current equality proposal, where structures and arrays compare identity. Swift's model, where `==` needs an `Equatable` conformance and `===` compares identity.
- Reason: the kind of the type explains the meaning of `==`.

## D17. Closeness to Swift

- Observation: the model is close to Swift's value and class core. It leaves out inheritance, protocols, `weak` and `unowned`, and noncopyable types. It differs in D15, D16, and in handling cycles through the GC.
- Discussion: the closeness felt disappointing at first. Arguments for accepting it:
  1. Independent reasoning from Matcha's goals arrived where Swift arrived after years of production use.
  2. The memory model is infrastructure, and it should be boring.
  3. Every unfamiliar idea costs users effort (Steve Klabnik's "strangeness budget"). Matcha should spend that budget on match-first control flow, structural data, and explicit boundaries.
- Original parts: changeable `for` and `match` bindings, equality without ceremony, the diagnostic for unused `var` copies, and mutation through open shapes (D19).

## D18. Order of features

- Decision: value semantics comes first, then explicit generics, then open shapes.
- Alternative: generics first.
- Reasons:
  1. With reference semantics, every structure is a pointer, so generics could use one compiled copy for all types (erasure). With value semantics, values have different sizes, so generics need monomorphization or size-and-copy dictionaries. Generics built first would likely use erasure and need a rebuild.
  2. An open shape like `{ name: string, .. }` is an implicit generic: the `..` is a hidden type parameter with a "has field" constraint. Open shapes can reuse the generics machinery (instantiation, caching, name mangling, substitution).
- Lowering options for generics and open shapes: monomorphization (Zig, Rust, C++), a hidden field-offset argument (Ohori's 1995 scheme for record polymorphism), or Go's hybrid of one copy per memory layout class plus a dictionary. Start with monomorphization.

## D19. Mutation through open shapes (future direction)

- Idea: `item rename(&user: { name: string, .. }, name: string)` changes one field of any structure that has it, in place, without sharing.
- Prior art found:
  1. Elm and PureScript: row-polymorphic record update, `{ r | name : String } -> { r | name : String }`. By the mutable value semantics equivalence (an `inout` parameter means "take the value and return a changed one"), this has the same meaning. So its soundness is known.
  2. PureScript `Record.ST`: in-place `poke` on any record with a given label, but only on an `STRecord` inside the `ST` monad, with type-level label proxies.
  3. Roc: open records, immutable semantics, in-place updates only as an optimization for unique values.
  4. Swift: `inout T` with a `WritableKeyPath`, nominal and explicit.
  5. TypeScript: open shapes with shared mutation, and unsound for writes.
  6. Go: field access through type sets (golang/go#48522) was disabled in Go 1.18 and has not shipped.
- A first search found no language that combines open records with in-place borrowed mutation.
- Advantage over Elm and PureScript: the row variable can stay anonymous, because nothing is returned.
- Required rules: opaque structures never match an open shape on an `&` parameter, and field types match exactly for writes.

## D20. Implementation staging

- Decision: switch the semantics before the memory representation. Copy on assignment while values stay boxed, and move to an inline representation later.
- Alternative: switch semantics and representation together.
- Reasons: the inline representation touches most of the LLVM code generation and its tests, but users cannot observe it. The semantics switch is a series of medium changes, mostly in the checker plus one copy-insertion pass. Identity structures keep today's representation.

## Evidence from the Pickware business platform

The `pickware-business-platform` server code (NestJS, TypeORM) was checked against the model:

1. Clean under both models: pure computations such as `computeOrderFeeCycleSegments()`, `CartService::computeTiers()`, and thin controllers like `UsageReportController`, which already passes IDs to services.
2. Better with value semantics: `CartService::createCart()` changes the caller's DTO argument (`cartDto.items = ...`). `admin-service.ts` renames a field on a loaded entity while building a response. Both become compile errors or harmless copies.
3. Behavior that silently differs: `ShopDeletionService::expireStagingShopSubscription()` changes `shop.stagingShop.subscription` and saves it. With value semantics, it changes and saves a copy, and the caller's `shop` keeps the old state.
4. Awkward: bidirectional entity graphs (`SubscriptionItem.subscription` and `Subscription.items`, `Shop.productionShop` and `Shop.stagingShop`) must become IDs. Stateful singleton services need identity structures (D4). Concurrent access to a service with changing state needs a future concurrency design.

## Open topics from the discussion

1. Closures: capturing a `var` by value or by reference brings back the sharing question. Swift boxes captured variables, which is hidden sharing.
2. Concurrency: values are safe to send between tasks, but identity objects are not. Swift added actors for this.
3. Stale IDs: an index into an array is a reference without memory danger, but it can refer to the wrong element after a removal. Opaque ID types help, and generational IDs need generics.
4. Changing a type between value and identity changes the meaning of every assignment of that type, and the compiler cannot flag it.
5. A shorthand receiver `&self` without the type.

## Sources

- [Implementation Strategies for Mutable Value Semantics (JOT 2022)](https://www.jot.fm/issues/issue_2022_02/article2.pdf)
- [Native Implementation of Mutable Value Semantics](https://arxiv.org/pdf/2106.12678)
- [PureScript Record.ST](https://pursuit.purescript.org/packages/purescript-record/2.0.2/docs/Record.ST)
- [Roc language reference: types](https://roc-lang.org/docs/main/langref/types/)
- [Roc: functional programming and in-place mutation](https://www.roc-lang.org/functional)
- [golang/go#48522](https://golang.org/issue/48522)
- [Go blog: core types](https://go.dev/blog/coretypes)
- [Row polymorphism (Wikipedia)](https://en.wikipedia.org/wiki/Row_polymorphism)
- [Valen](https://github.com/valen-lang/valen)
