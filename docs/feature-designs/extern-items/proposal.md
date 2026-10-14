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

## AI Generated

### Interop layers

Interop arrives in three layers. Each layer needs more from the language.

1. Integers and pointers only. This needs extern items, C integer types (`c_int` and others), and a way to link. A thin wrapper around a library already makes SQLite usable.
2. Libraries with handles, used directly, such as SQLite, libpq, or zlib. This needs a C pointer type (`c_pointer`, with `null`), a C string type with explicit conversion in both directions, resource cleanup (for example `defer`), and error handling for C return codes.
3. Callbacks and structures passed by value, such as libcurl or raylib. Callbacks need function values. Structures passed by value need value semantics stage 6 (inline representation) and per-platform classification of the C calling convention.

Correction to "Value semantics comes first" above: only layer 3 needs value semantics. Layers 1 and 2 work with today's representation.

### Glue in Matcha

A library module has two layers. Non-exported items use C types, and the module system keeps them private. Exported items use Matcha types, and other modules see only those.

```matcha
// sqlite.mt
item sqlite = link "sqlite3.c";

item sqliteOpen(path: cstring, &handle: c_pointer): c_int = sqlite.symbol("sqlite3_open");
item sqliteOk: c_int = 0; // SQLITE_OK is a C macro, not a symbol

export item Connection = opaque identity structure {
    private handle: c_pointer;

    constructor (handle: c_pointer) {};
};

export item open(path: string): Connection = {
    var handle = c_pointer.null;
    val status = sqliteOpen(path.toCString(), &handle);
    // map status to an error
    return Connection(handle);
};
```

1. A C out-parameter like `sqlite3 **db` maps to an `&` parameter. `&` already means "the callee writes into my place".
2. A C handle maps to an `opaque identity structure` with a private `c_pointer` field. It is shared, and outside code cannot reach the raw pointer.
3. In this example, any module can call `Connection(someRandomPointer)`. Glue code needs a constructor that only the type itself can call.
4. A string that C returns must be copied into a Matcha string, because C owns that memory.

### Glue in Zig

Some headers are hard to use from Matcha declarations. Zig imports C headers with `@cImport`, so a small Zig layer handles:

1. Macros, such as `#define` constants. They are not symbols, so Matcha would have to redeclare them by hand.
2. Inline functions and variadic functions like `printf`.
3. Callbacks, until Matcha has function values.

Zig interop works through Zig functions with C-compatible signatures (`export fn`, integers, pointers, `extern struct`). Matcha calls them like C functions. The runtime already works this way: `runtime/matcha_runtime.zig` exports its functions with `@export`, and every Matcha program links `libmatcha_runtime.a`. Full Zig interop with slices, error unions, or `comptime` generics is not realistic, because Zig has no stable ABI.

### Priorities

1. Write the standard library in Matcha where this is safe and practical: HTTP, JSON, and the Postgres wire protocol. Programs then stay one static binary.
2. Terminate TLS in front of the service, for example in Caddy, nginx, or a cloud load balancer. Cryptography needs constant-time code and security maintenance, so a rewrite is not safe.
3. Use C for libraries that are hard to rewrite safely, such as SQLite and compression.
4. Link C statically and compile it from source per target (see the toolchain proposal), so that deployment stays one binary.
