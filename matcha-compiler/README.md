# Matcha Compiler

`matcha-compiler` is the current reference compiler for Matcha.

It is still early in development, but it already reads `.mt` source files, parses and analyzes them, emits LLVM IR, and links that IR together with the Matcha runtime into a native executable. The runtime currently uses Boehm GC (`bdw-gc`), and the final native link step is performed through `clang`.

> [!WARNING]
> This compiler is still experimental. Matcha is currently best understood as a fast-moving `v0.1.1` hobby language project rather than a stable platform.

## What this package contains

This directory contains:

- the Matcha CLI
- the compiler frontend and semantic analysis pipeline
- LLVM IR emission
- native build and run orchestration
- the Matcha runtime library
- unit and end-to-end tests
- example Matcha programs

## Currently implemented

The current compiler supports a practical core language, including:

- `val` and `var`
- `int`, `boolean`, and `string`
- arrays with indexing, `append`, and `length`
- structures with fields, methods, and type functions
- `if`, `while`, `for`, `loop`, and `match`
- built-ins such as `printInt`, `printString`, `readFile`, `readLine`, and `getArguments`

For the most accurate view of what works today, use the examples in [`examples/`](./examples) and the tests in [`tests/e2e/`](./tests/e2e).

## Quick start

### Install released compiler with Homebrew tap

On macOS:

```sh
brew tap mario-nowak/tap
brew install mario-nowak/tap/matcha-lang
matcha --help
```

Then try an example program from this repository:

```sh
git clone https://github.com/mario-nowak/matcha.git
cd matcha/matcha-compiler
matcha run examples/learning-matcha.mt
```

If `clang` is not available yet, install Xcode Command Line Tools:

```sh
xcode-select --install
```

### Build compiler from source

From `matcha-compiler/` on macOS:

```sh
brew install mise llvm@20 bdw-gc
mise trust
mise install
mise run build
./zig-out/bin/matcha run examples/learning-matcha.mt
```

## macOS setup

The documented source-build setup path currently targets macOS and uses Homebrew plus `mise`.

### 1. Install system dependencies

```sh
brew install mise llvm@20 bdw-gc
```

### 2. Trust the repository tool configuration

```sh
cd matcha-compiler
mise trust
```

### 3. Install the declared toolchain

```sh
mise install
```

That gives you:

- `zig 0.15.1`
- Homebrew LLVM 20 on `PATH`
- `clang` and LLVM tools for linking and IR workflows
- `bdw-gc` for the runtime and final native binary

## Installing the released compiler manually

If you prefer release artifacts instead of Homebrew, download the latest compiler release from GitHub and extract it so that the bundled layout stays intact:

```text
bin/matcha
lib/libmatcha_runtime.a
```

`matcha` also expects:

- `clang` on `PATH`
- `bdw-gc` installed through Homebrew

After extraction, verify the install with:

```sh
matcha --help
```

## Building the compiler

From `matcha-compiler/`:

```sh
mise run build
```

Equivalent raw Zig command:

```sh
zig build
```

The built compiler binary is placed at:

```text
zig-out/bin/matcha
```

## Using the compiler

Show CLI help:

```sh
./zig-out/bin/matcha --help
```

Emit LLVM IR:

```sh
./zig-out/bin/matcha emit examples/learning-matcha.mt
```

By default, this writes:

```text
examples/learning-matcha-emission.ll
```

Build a native binary:

```sh
./zig-out/bin/matcha build examples/learning-matcha.mt
./examples/learning-matcha
```

By default, `build` writes a binary next to the source file using the source stem as the output path.

Build to an explicit output path:

```sh
./zig-out/bin/matcha build examples/learning-matcha.mt --output ./tmp/learning-matcha
./tmp/learning-matcha
```

Compile and run in one step:

```sh
./zig-out/bin/matcha run examples/learning-matcha.mt
```

Pass program arguments through `run`:

```sh
./zig-out/bin/matcha run examples/customer-import-audit.mt -- ./sample-input.txt
```

## Common development commands

Using `mise` tasks:

```sh
mise run check          # compile-check the project
mise run build          # build the compiler and runtime
mise run test-compiler  # run Zig unit/integration tests wired through build.zig
mise run e2e            # run end-to-end tests
mise run test           # run compiler tests and e2e tests
mise run build-compiler # optimized ReleaseFast build
```

Raw Zig equivalents:

```sh
zig build check
zig build
zig build test --summary all
zig test tests/e2e/tests.zig
```

## Tests

The test suite covers both internal compiler behavior and real compile-and-run workflows.

- `zig build test --summary all` runs unit and integration tests through `build.zig`
- `zig test tests/e2e/tests.zig` runs end-to-end tests against real Matcha source programs
- `mise run test` runs the full local test workflow

Run end-to-end tests with:

```sh
mise run e2e
```

or:

```sh
zig test tests/e2e/tests.zig
```

## How the pipeline works today

At a high level:

1. `src/cli/` parses commands such as `emit`, `build`, and `run`
2. `src/compiler/` lexes, parses, performs semantic analysis, and emits LLVM IR
3. `src/toolchain/` takes the emitted IR and performs the native link/run workflow
4. `runtime/` provides the runtime functions linked into compiled programs
5. the final link step combines:
   - emitted LLVM IR
   - static `libmatcha_runtime.a`
   - `bdw-gc`
6. the result is a native executable

Command behavior:

- `matcha emit` → compiler only, writes LLVM IR to disk
- `matcha build` → compiler plus native link step, produces a binary
- `matcha run` → compiler plus native link step plus process execution, using temporary artifacts

## Repository layout

```text
matcha-compiler/
├── src/
│   ├── cli/            # command parsing and CLI execution
│   ├── compiler/       # lexer, parser, semantic analysis, LLVM IR emission
│   └── toolchain/      # native build/run orchestration and linking
├── runtime/            # Matcha runtime linked into compiled programs
├── tests/
│   └── e2e/            # end-to-end tests over real Matcha programs
├── examples/           # sample Matcha source programs
├── build.zig           # Zig build graph
└── .mise.toml          # local toolchain and task definitions
```

## Examples

Example programs live in [`examples/`](./examples):

- [`learning-matcha.mt`](./examples/learning-matcha.mt) — a guided tour of the currently implemented language
- [`aoc-2024-01.mt`](./examples/aoc-2024-01.mt) — Advent of Code-style parsing and list processing
- [`customer-import-audit.mt`](./examples/customer-import-audit.mt) — a more idiomatic example with structures, normalization, and decision logic

If you want one file to read first, start with [`examples/learning-matcha.mt`](./examples/learning-matcha.mt).

## Notes

- The documented setup currently targets macOS.
- Native linking expects Homebrew-installed `bdw-gc`.
- The final native link step currently shells out to `clang`.
