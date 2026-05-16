# Matcha goals

## Why Matcha exists

Matcha exists because I want a language that makes backend and service code feel more direct, more explicit, and harder to get subtly wrong.

A lot of application code is about shaping data, validating assumptions, branching on cases, and carrying that intent through many small transformations. In many mainstream languages, that work is either too dynamic, too implicit, or too noisy. Matcha is my attempt at a language that treats this style of programming as first-class.

The core idea is simple:

> Matcha should make complex data and control flow easier to express with confidence.

I want Matcha to feel good for code that spends its time parsing inputs, modeling structured data, branching on cases, transforming values, and producing reliable outputs.

## Language story

Matcha is an experimental compiled programming language for application and service code.

The language is centered around a few ideas:

- match-oriented control flow
- strong structural data modeling
- explicit behavior at boundaries
- fast feedback from the compiler
- practical deployment and runtime ergonomics

The goal is not to build a language for every domain. The goal is to build a language that is especially pleasant for data-heavy backend work, where correctness, readability, and iteration speed matter a lot.

If Matcha succeeds, it should let you write service code that is:

- fast to understand
- hard to misuse accidentally
- explicit without being ceremony-heavy
- efficient enough for real workloads
- easy to build and deploy

## What I want Matcha to optimize for

### 1. Match-first programming

I want `match` to be one of the defining features of the language, not an afterthought.

Many real programs are mostly case analysis:

- branching on state
- branching on input shape
- branching on success vs failure
- branching on domain variants
- branching on validation outcomes

Matcha should make that style feel natural. Multi-way branching should be clearer and safer than long chains of special cases. Exhaustiveness checking should be normal. Complex branching should stay readable.

```matcha
val label = match response {
    .Ok(user) => user.name,
    .NotFound => "missing",
    .Unauthorized => "forbidden",
};
```

I also want subjectless `match` to make condition chains feel like one coherent branching construct instead of a pile of `else if` cases:

```matcha
val bucket = match {
    score >= 90 => "excellent",
    score >= 75 => "good",
    score >= 60 => "pass",
    else => "fail",
};
```

### 2. Structural data modeling with guardrails

A lot of application programming is not about pointer tricks or manual memory management. It is about modeling data honestly.

Matcha should make it easy to express:

- exact data structures
- open and closed structural constraints
- tagged unions
- explicit boundaries between nominal and structural meaning
- invariants where they matter

I want the language to support convenient data shaping, but without the accidental conformance and ambiguity that often show up in more weakly disciplined structural systems.

For example, I want a clear distinction between exact structures and open structural requirements:

```matcha
item User = structure { name: string; };
item UserUpdate = structure { name: string; wasValidated: boolean; };

item greetExact(user: { name: string }) = "Hello, " + user.name;
item greetOpen(user: { name: string, .. }) = "Hello, " + user.name;

val update = UserUpdate { name = "Tom", wasValidated = true };

greetOpen(update);  // OK
// greetExact(update); // error: extra field at exact boundary
```

Open shapes are useful when a function needs certain data. Exact boundaries are useful when a function means exactly what it says.

That same idea should carry through boundaries. If a value has more fields than a target type expects, crossing that boundary should be explicit rather than accidental:

```matcha
item User = structure { name: string; };
item UserUpdateDto = structure { name: string; wasValidated: boolean; };

val dto: UserUpdateDto = .{ name = "Tom", wasValidated = true };
val user = User { ..dto };
```

I also want Matcha to make semantic meaning easy to express, especially when plain primitives are too weak:

```matcha
item UserId = opaque string;
item OrgId = opaque string;

item loadUser(id: UserId) = { /* ... */ };

val userId = UserId("abc");
val orgId = OrgId("xyz");

loadUser(userId); // OK
loadUser(orgId);  // error
```

And for some domains, I want nominal boundaries and invariants to be available for larger data too. Some values should not be constructible as arbitrary records just because the fields line up.

```matcha
item Email = opaque structure {
    public value: string;

    constructor (value: string) {
        // reject invalid email strings here
    };
};
```

### 3. Explicitness without unnecessary verbosity

I do not want a language where tiny implicit changes cause major behavioral changes. I also do not want a language where every useful thing takes too much syntax.

Matcha should aim for:

- explicit control flow
- explicit value usage
- explicit error handling
- explicit boundary crossing when representation or meaning changes

I want code to read as though the programmer made the important choices on purpose. A change in shape, meaning, or invariants should usually appear as a visible step in the code, not as a silent side effect of type compatibility.

At the same time, it should still feel lightweight to write. The goal is not maximal ceremony. The goal is clarity.

### 4. Developer velocity

I care a lot about iteration speed.

That includes:

- fast compile times
- useful diagnostics
- straightforward tooling
- simple local workflows
- practical commands for building, testing, and running code

I want Matcha to support a style of development where the compiler is a fast and helpful partner.

### 5. Deployment ergonomics

I want the output of Matcha to be easy to ship.

That means aiming for:

- simple build steps
- practical packaging
- straightforward release artifacts
- minimal operational friction

The long-term ideal is that Matcha programs should be boring to deploy.

### 6. Performance that is good enough for real backend work

Performance matters, but not at any cost.

I want Matcha to be fast enough to be a serious option for real services and command-line tools. I care about compilation speed and runtime performance. But I do not consider manual memory management or ownership complexity to be mandatory requirements for this project.

Garbage collection is an intentional choice, not a temporary compromise.

## Values

These are the values I want Matcha to embody.

### Readability over cleverness

Code should usually say what it means directly. The language should reward straightforward code more than clever tricks.

### Honest semantics

Features should compose in ways that are understandable. Hidden magic should be rare. When something is exact, open, nominal, structural, recoverable, or not recoverable, that should be visible in the language model.

### Strong defaults, explicit escape hatches

The default path should be ergonomic, readable, and safe for common application code. But when code crosses an important boundary, I want that step to become explicit rather than invisible.

That includes things like:

- moving from open structural data into an exact domain type
- moving from a plain primitive into a meaning-carrying opaque type
- introducing stronger invariants through constructors or opaque structures
- choosing stricter modeling when convenience alone would be too loose

Matcha should make the common case pleasant without making important distinctions disappear. I want convenience by default, but I do not want convenience that erases meaning.

### Compiler help over runtime surprise

Whenever practical, mistakes should be caught early:

- non-exhaustive logic
- unused values
- incorrect structure usage
- incompatible control-flow results
- invalid type combinations

### Practicality over purity

I am not trying to build a mathematically pure language or a research language. I want something useful for real codebases.

### A coherent object and type story

I want the type system and data model to feel like one system, not a pile of disconnected features.

## Non-values

Just as important: there are things Matcha is not trying to optimize for.

### Matcha is not a systems programming language

I am not trying to compete with Zig, Rust, or C on low-level control.

Matcha is not optimized for:

- manual memory management
- no-runtime environments
- kernel or embedded programming
- fine-grained aliasing control
- low-level hardware work

### Matcha is not trying to eliminate all shared mutability through ownership machinery

I do not currently view ownership and borrow checking as the right default tradeoff for this language.

That does not mean correctness does not matter. It means I want to pursue correctness through different tools.

### Matcha is not trying to maximize abstraction power at any cost

I do not want a language that becomes harder to read because it can express every abstraction pattern imaginable.

Abstraction matters, but it should serve clarity.

### Matcha is not trying to be everything to everyone

This project is intentionally opinionated. It is okay if some people want a language with different tradeoffs.

## Current direction

Today, Matcha is still early and incomplete, but the current direction is already visible.

The compiler already includes a meaningful core of:

- values and variables
- integers, booleans, and strings
- arrays
- structures
- loops and `if`
- `match`
- LLVM IR emission
- native binary generation
- a runtime with garbage collection

This is enough to validate the core feel of the language, but not enough yet to call the language broadly complete.

## Features I still want to add

The exact roadmap will change, but the kinds of features I currently expect Matcha to grow include:

### Better data and type modeling

- richer union support
- stronger error modeling
- more complete shape / contract / opaque type story
- generic programming that stays readable
- type-level features only where they clearly improve real programs

### Better control-flow tools

- continued refinement of `match`
- better error propagation ergonomics
- panic and unrecoverable-error design
- control-flow features that make service code simpler rather than more magical

### Better standard-library and I/O story

- file and process ergonomics
- asynchronous I/O design
- more practical library support for real programs

### Better tooling

- stronger diagnostics
- editor support
- release/install story
- easier project setup and packaging

### More real-world examples

I want Matcha to be shaped by real programs, not only by language sketches. That means more example applications, more test cases, and more pressure from realistic backend workflows.

## Constraints and tradeoffs

I do not expect Matcha to become a perfect language. I care more about building a language with a strong center of gravity than one that tries to solve every possible problem elegantly.

That means some features may stay out entirely. Others may arrive later than expected. Some ideas that sound attractive in isolation may still be rejected if they weaken the overall direction.

I also expect the language to change significantly while it is still pre-1.0.

## What success would look like

Matcha would be succeeding if it becomes a language where writing backend and service code feels:

- calmer
- clearer
- more explicit
- safer by default
- faster to iterate on

I want it to be a language where structured data and branching logic feel unusually pleasant, and where the compiler helps keep that code honest.

That is the point of the project.
