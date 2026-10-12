# Extern items proposal (draft)

Goal: call C libraries (for example raylib or SQLite) from Matcha, and let Zig or C programs call Matcha functions. Matcha emits LLVM IR and links with `clang`, so linking works today. The work is in the type mapping.

## Ideas

- Importing a C function is a normal function item whose body references a library item. The C name is a string, because C names are not always valid Matcha identifiers:

  ```matcha
  item sqlite = link "libs/sqlite3.a";

  export item open(path: cstring): c_int = sqlite."sqlite3_open";
  ```

  Other modules import `open` like any other item.
- `export` already means "visible to other modules", so exposing a function to C needs a different word.
- Strings cross the boundary explicitly. C functions take a C string type (working name `cstring`), and the caller converts with a method such as `.toCString()`. The compiler never copies silently.
- Value semantics comes first, because it gives structures a byte layout that can match C.
- Order of build support: first a `--link` CLI flag, then the `link` item, and a project file (`package.mon`) only when a setting has no other place.
- Later, `import "builtin"` can become a real `.mt` file of extern declarations shipped with the compiler. User code stays the same.

## Required type mapping

- C integer sizes (`c_int` and others), because Matcha's `int` is 64-bit.
- Floating-point types (`f32`, `f64`). raylib uses `float` almost everywhere.
- Structures passed by value with C layout. This is the hardest part: LLVM does not lower the C calling convention for structures, so the compiler must classify them per platform, as clang does.
- C strings, as above.

## Exposing Matcha functions to C

- A chosen, stable symbol name. The internal names (`matcha.module.main.function.parse`) contain dots.
- The C calling convention for parameters and return values.
- Runtime start-up: a library has no `main`, so the host must call an init function first, or the library initializes the GC on its first call.
- A way to build a static library instead of an executable.

## Open

- The keyword for exposing: `expose item`, or one `extern` keyword where a missing body means import and a body means expose.
- `sqlite."sqlite3_open"` (string member access) versus `sqlite.symbol("sqlite3_open")`.

## Garbage collector

Pointers passed to C during a call stay alive, because the Boehm GC scans the stack. A pointer that C keeps in its own memory after the call is invisible to the GC and can dangle.

## Cheap first step

Write a thin C wrapper around the library that uses only 64-bit integers and pointers, and call it through extern items. That needs no floats and no structures passed by value.
