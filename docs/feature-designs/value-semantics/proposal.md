---
author: @mario-nowak
llm: claude-opus-5.5
---

# Value semantics proposal (draft)

Decided on 2026-10-09. The model below replaces the first draft, which had storable `*T` and `*var T` references and prefix arrays (`[]T`). Value semantics comes next, before generics, because generics need monomorphization once values have different sizes.

Matcha moves from reference semantics to value semantics. Signatures, call sites, and type declarations then show every mutation and every sharing ("nothing happens silently").

The alternatives considered, and why they were dropped, are in [decision-record.md](decision-record.md).

## The model in four rules

1. Everything is a value. Assigning or passing a value gives an independent copy.
2. `var` lets you change your copy. `val` does not.
3. A function that changes your value declares the parameter as `&name: T`, and you pass it with `&x`. The change is visible after the call.
4. When many places must see one thing, declare it as an `identity structure`. Everyone then holds the same object.

One question decides every case: "Does anyone else see my change?" Only if the thing is an identity structure, or if you passed it with `&`.

## Bindings

`val` is deep: the binding and all its parts never change. `var` allows changing the binding and all its parts.

```matcha
item Point = structure { x: int; y: int; };
item Line = structure { from: Point; to: Point; };

val line = Line { from = .{ x = 0, y = 0 }, to = .{ x = 5, y = 5 } };
line.to.x = 7; // error: `line` is val, so its parts are frozen too

var path = line; // an independent copy
path.to.x = 7; // OK, and `line` is unchanged
```

`val b = a` may reuse the storage of `a`, and a move on last use is an invisible optimization. Semantically, `b` is an independent value.

The compiler warns when a `var` binding never changes: "`x` never changes, use `val`". A reader can then trust that every `var` changes somewhere.

## Parameters and `&`

Parameters are immutable values. Nothing can change a parameter while the function runs, so the compiler may pass large values by pointer. The program cannot observe the difference.

A function that changes an argument marks the parameter with `&` before its name. The call site passes `&x`, and `x` must be a `var` place. The same marker appears in both places: `&line` receives what `&path` passes.

```matcha
item stretch(&line: Line): unit = {
    line.to.x += 1;
};

var path = Line { from = .{ x = 0, y = 0 }, to = .{ x = 5, y = 5 } };
stretch(&path);
```

A method that changes its receiver takes `&self`. The call `x.method()` passes `&x` implicitly, and `x` must be a `var` place.

```matcha
item Counter = structure {
    names: string[];

    item add(&self: Counter, name: string): unit = { ... };
    item countOf(self: Counter, name: string): int = { ... };
};

val frozen = Counter { names = [] };
frozen.add("tea"); // error: `add` takes `&self`, and `frozen` is val

var words = Counter { names = [] };
words.add("tea"); // OK
```

`&` marks how a parameter is passed. It is not part of the type, so it cannot appear in fields, arrays, or return types, and a reference never outlives the call. A reference can point into a field, an array element, or a union payload, because it cannot go stale during the call. There is no read-only `&`: an immutable parameter already gives that guarantee.

Passing a value to a parameter never copies or moves it. The caller keeps its value. A function that stores a parameter, for example `self.users.append(user)`, copies it. Copy-on-write keeps that copy cheap.

Precedent for a marker before the parameter name: Mojo's `mut x: T` and C#'s `ref x`. Rust users may read `&self` as read-only at first, because Rust spells the changeable form `&mut self`.

## Arrays

There is one growable array type `T[]` with value semantics, like Swift's `Array`. There is no separate slice or `ArrayList` type, so there are no stale views. The array syntax stays postfix, as Matcha has it today. The planned optional spelling is also postfix (`User?`), so all type modifiers sit on the right: `User?[]` is an array of optional users, and `User[]?` is an optional array.

```matcha
var first: int[] = [1, 2, 3];
var second = first; // an independent copy
second.append(4); // `first` still has 3 elements
```

Arrays use copy-on-write. `var second = first` shares the buffer and marks it as shared. The first write to a shared buffer copies it, so only real divergence costs anything. The Boehm GC has no reference counts, so a shared flag replaces the count. Once a buffer is shared, the first write from each holder copies it. That can cause one unnecessary copy, but it is simple and correct.

Copies are implicit. There are no moves and no "used after move" errors.

## Copies with changes

Spread builds a new value from an existing one. It is the idiomatic way to copy with changes:

```matcha
var draft = .{ ..user, name = "Tom" };
var more = [..numbers, 4];
```

Spread is construction, so it follows the construction rules. It does not work for opaque structures.

## `for` and `match` bindings

A `for` or `match` binding is the element or payload itself, not a copy. It inherits the mutability of the subject. Swift copies here, so this is a deliberate difference.

```matcha
var points: Point[] = [.{ x = 1, y = 1 }, .{ x = 2, y = 2 }];
for point in points {
    point.x *= 10; // changes the element in `points`
}

var shape: Shape = .Circle(.{ radius = 2 });
match shape {
    .Circle(circle) => circle.radius *= 2, // changes the payload of `shape`
    .Empty => {},
};
```

Inside the loop or the arm, the subject can only change through the binding. `points.append(point)` inside the loop above is an error.

## Identity structures

An `identity structure` is shared. Assignment copies the reference, not the object. Identity structures are the only way to store a reference.

No single binding owns an identity object, so each field declares its own mutability. A field is fixed after construction unless it is declared `var`. `val` and `var` on the binding only control which object the binding refers to.

```matcha
item PriceCache = identity structure {
    currency: string; // fixed after construction
    var hits: int; // can change through any reference

    item create(currency: string): PriceCache = .{ currency = currency, hits = 0 };

    item record(self: PriceCache): unit = {
        self.hits += 1; // no `&` needed: `hits` is a var field
    };
};

val cache = PriceCache.create("EUR");
val sameCache = cache; // the same object
sameCache.record();
cache.hits; // 1

cache.currency = "USD"; // error: `currency` is not a var field
```

`var` fields only exist in identity structures. In a value structure, the binding decides mutability, and a `var` field would break deep `val`.

Copying a value stops at identity fields. The value is copied, and the identity object it refers to is shared.

Use identity structures for things with a lifecycle: services, caches, connections. Keep data as values, and link data through IDs into a container that owns it.

```matcha
item Task = structure {
    name: string;
    done: boolean;
    dependencies: int[]; // indexes into Project.tasks
};

item Project = structure {
    tasks: Task[];

    item complete(&self: Project, id: int): unit = {
        self.tasks[id].done = true;
    };
};
```

## Opaque structures

`opaque` is independent of value and identity. It controls who can construct a structure and who can write its fields.

1. Only the constructor creates an opaque structure, also inside the type. Literals and spread are errors everywhere. To find every place a value is created, read the constructor.
2. All fields are readable from outside by default. Only the type's own methods can write them, through `&self`. Each changing method keeps the invariant itself, as in a TypeScript class with private fields.
3. `private` hides a field from outside code completely.
4. Replacing the whole value is allowed, because the new value went through the constructor.
5. Copies are not creations. `var other = range;` works anywhere, because a copy of a valid value is valid.

```matcha
item DateRange = opaque structure {
    start: int;
    end: int;
    private createdBy: string;

    constructor (start: int, end: int, createdBy: string) {
        // reject start > end here
    };

    item extendBy(&self: DateRange, days: int): unit = {
        // reject negative days here
        self.end += days;
    };
};

var range = DateRange(10, 20, "mario");
range.start; // OK
range.start = 30; // error: fields of an opaque structure are read-only outside it
range.createdBy; // error: `createdBy` is private
range.extendBy(5); // OK
range = DateRange(1, 5, "mario"); // OK
```

Rule 2 is necessary with value semantics. Without it, `var` would give write access to every field of a copy and bypass the constructor's invariant.

`private` is only allowed in opaque structures. Outside code constructs a plain structure with a literal, and the literal must set every field.

Matcha has no zero values. Nothing creates an opaque structure without its constructor.

## Who can change a field

| Kind | Who can change a field |
|---|---|
| `structure` | anyone, through a `var` binding |
| `opaque structure` | only the type's own methods, through `&self` |
| `identity structure` | anyone, but only fields declared `var` |
| `opaque identity structure` | only the type's own methods, and only fields declared `var` |

Each keyword answers one question: `opaque` for "I need invariants", `identity` for "two places must see the same changes". Further structure modifiers need a strong case, because each one multiplies the combinations.

## Equality

Values compare contents. Identity structures compare identity.

```matcha
Point { x = 1, y = 2 } == Point { x = 1, y = 2 }; // true
PriceCache.create("EUR") == PriceCache.create("EUR"); // false
```

## Known cost

Value semantics has its own silent mistake: you expect sharing but get a copy. Two things limit it:

1. A function that changes a parameter without `&` is a compile error.
2. The remaining case is a local copy: `var copy = x; copy.change();` when you meant to change `x`. A diagnostic can catch it: "this `var` copy changes, but nothing reads it afterward". This fits the existing unused-value checks.

The cost of a copy is also invisible in the code. Copy-on-write makes most copies free. An optional compiler flag lists the places where deep copies can happen, for when you optimize.

## Relation to other languages

The model is close to Swift: `struct`, `final class`, `inout`, and `mutating`. The differences:

1. `for` and `match` bindings change the original. Swift copies.
2. `==` needs no conformance. It is contents for values and identity for identity structures.
3. The garbage collector handles cycles between identity objects. There is no `weak` or `unowned`.
4. There is no class inheritance.

For Go users: structures already copy in Go, `func (c *Counter) Add()` becomes `&self: Counter`, and `f(&x)` stays `f(&x)`. The adjustments are `val` by default, arrays as real values, and IDs or identity structures instead of `[]*User`. Two Go traps disappear: changing a `range` copy, and `append` overwriting a shared slice.

## Implementation stages

The semantics can switch before the memory representation does. Each stage ships on its own.

1. Checker rules. `NodeTypeAnalyzer::checkPlaceNode()` (`matcha-compiler/src/compiler/semantic_analysis/type_checking/node_type_analyzer.zig`) checks only identifier targets for mutability today. Member and index targets must walk to their root binding. This makes `val` deep and parameters immutable.
2. `&` parameters. The parser accepts `&` before a parameter name and before a call argument. The checker requires a `var` place and adds the implicit receiver `&`. The code generator passes the address of the binding's stack slot.
3. Copy on assignment, still boxed. Structures, unions, and arrays stay heap-allocated. The compiler inserts a copy where an aggregate moves from a place into another place: binding initialization, assignment, field store, array element store, and `append`. Temporaries such as call results and literals need no copy. The copy recurses through nested values and stops at strings and identity fields. This is the actual semantics switch.
4. Identity structures and equality. Identity structures keep today's representation and skip the copy from stage 3. Value equality replaces identity equality for structures, arrays, and unions.
5. `for` and `match` bindings as places, with the rule that the subject only changes through the binding.
6. Inline representation. Structures become LLVM struct values, and arrays and unions store their elements and payloads inline. This touches most of the LLVM code generation and its tests. Users cannot observe it, so it can wait until performance or C interop needs it.
7. Copy-on-write for arrays, with a shared flag on the buffer instead of a reference count.

## Open points

1. Overlapping `&` arguments. `swap(&a[0], &a[1])` passes two references into `a`. Swift rejects this statically and offers `a.swapAt(0, 1)`.
2. `&` into an identity object's field. `f(&service.prices)` can conflict when `f` also reaches `service` another way. Options: a runtime check like Swift's exclusivity enforcement, or documentation.
3. Construction of identity structures, and whether `opaque identity structure` needs extra rules.
4. Whether unions are always values.
5. Copy cost of stage 3 until copy-on-write exists.

## Future direction: mutation through open shapes

With value semantics, an `&` parameter can use an open shape:

```matcha
item rename(&user: { name: string, .. }, name: string): unit = {
    user.name = name;
};
```

This changes one field of any structure that has it, in place, without sharing. It is equivalent to row-polymorphic record update in Elm or PureScript, so its soundness is known. Unlike there, the row variable can stay anonymous, because nothing is returned. A first search found no language that combines open records with in-place borrowed mutation.

Rules it needs:

1. Opaque structures never match an open shape on an `&` parameter. That would bypass the opaque write rule.
2. Field types match exactly for writes. A field with a nested open shape can be written through, but not replaced as a whole.

Open shapes are implicit generics, so this comes after explicit generics.

## To do at the switch

- Revise `docs/feature-designs/equality/proposal.md`. Structure and array equality is reference identity there, and must become value equality.
- Update the `Email` example in `docs/goals.md`. It writes `public value: string`, but public is now the default.
- Checkpoint: port one non-toy program before committing to the details. The git stash entry "Add programs to decide value semantics" has paper ports, including `todo-api-round-trip-value-semantics.mt`. Those ports use the first draft's syntax.
- Existing code gets ported in one step. There are no migration guardrails.

## Effect on C interop

Value semantics makes C interop easier (see `extern-items/proposal.md`). After stage 6, a structure is its bytes, so it can match a C struct and be passed by value. Arrays of structures become contiguous. An `&` parameter maps to `T*`.
