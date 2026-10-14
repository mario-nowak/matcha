---
author: claude
status: draft
---

# Toolchain proposal

## AI Generated

### Current state

`Linker` (`matcha-compiler/src/toolchain/linker.zig`) calls the system `clang` and finds the Boehm GC through Homebrew (`brew --prefix bdw-gc`), then links it with `-lgc`. So:

1. Building a Matcha program needs clang and Homebrew's `bdw-gc` on the build machine.
2. The binary probably links `libgc` dynamically, so the machine that runs it also needs the library.
3. Cross-compiling does not work.

This conflicts with the goal "boring to deploy".

### Direction: build through the Zig toolchain

Zig ships a C compiler (`zig cc`, with clang inside) and the C libraries of many targets: glibc versions, musl, macOS, and Windows. `zig cc -target x86_64-linux-musl file.c` builds for Linux on a Mac with nothing else installed. Matcha does not build its own C toolchain. It uses Zig's, by shipping or requiring the `zig` binary.

Then `matcha build --target x86_64-linux-musl` does this:

1. It emits LLVM IR for the target.
2. It compiles the Zig runtime for the target.
3. It compiles the Boehm GC from source and links it statically.
4. It compiles sources from `link "x.c"` and `link "x.zig"` items for the target.
5. It links everything statically against musl.

The result is one static Linux binary without dependencies. Build products are cached per target, so a library like SQLite compiles once per target.

### Sources instead of `.a` files

A `.a` file contains machine code for one target, so a prebuilt `.a` needs one copy per target. `link "sqlite3.c"` compiles from source for any target, so prefer sources.

### Caveats

1. musl allocates memory a little slower than glibc, and its DNS resolution differs slightly.
2. macOS targets cannot be fully static, because Apple requires dynamic linking against its system library.
3. The Zig distribution adds roughly 50 MB to the Matcha download.

### Comparison with Go

Pure Go cross-compiles with `GOOS=linux GOARCH=arm64 go build`. With cgo, cross-compiling needs a C toolchain per target, binaries often depend on the target's glibc version, and every C call switches stacks. With the Zig toolchain and static linking, Matcha avoids the first two. Matcha has no goroutine stacks, so a C call is a normal function call.
