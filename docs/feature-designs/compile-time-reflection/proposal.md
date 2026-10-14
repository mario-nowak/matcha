---
author: claude
status: draft
---

# Compile-time reflection proposal

## AI Generated

Ideas under discussion.

- Builtins with an `@` prefix that describe types at compile time, like Zig's `@typeInfo`: for example `@kind(T)`, `@fields(T)`, and `@field(value, name)`.
- A `for` over `@fields(T)` that the compiler unrolls per field, inside monomorphized generic code. No runtime reflection.
- Reflection respects visibility: outside a module, `@fields(T)` lists only fields that code could read anyway. Opaque types are never built from fields.
- Main use case: JSON encoding and decoding for any structure. Others: equality, hashing, debug printing.
- A model to look at: Swift's `Codable`, where the compiler generates the implementation once a type declares the conformance.
- Possible later step: annotations like `@route(...)` that compile-time code reads.
- Alternatives: Go's runtime reflection (cost and errors at runtime), Rust's derive macros (a separate macro system that generates hidden code).
