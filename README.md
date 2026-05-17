# Matcha

[![CI](https://github.com/mario-nowak/matcha/actions/workflows/ci.yml/badge.svg)](https://github.com/mario-nowak/matcha/actions/workflows/ci.yml)

<p align="center">
  <img src="./assets/matcha-1024.png" alt="Matcha logo" width="180" />
</p>

Matcha is an experimental compiled programming language with a GC-managed runtime. The project is still early in development, but it already includes a real compiler, runtime, and CLI capable of producing native binaries from Matcha source code.

## What Matcha looks like

Snippet adapted from [`matcha-compiler/examples/learning-matcha.mt`](./matcha-compiler/examples/learning-matcha.mt):

```matcha
val numbers = [2, 3, 4, 5];
var sum = 0;
for number in numbers {
    sum += number;
}

val label = match sum {
    14 => "expected total",
    else => "unexpected total",
};
printString(label);

item Point = structure {
    x: int;
    y: int;

    item origin(): Point = .{
        x = 0,
        y = 0,
    };

    item invert(self: Point): unit = {
        self.x *= -1;
        self.y *= -1;
    };

    item movedBy(self: Point, other: Point): Point = .{
        x = self.x + other.x,
        y = self.y + other.y,
    };

    item length(self: Point): int = self.x * self.x + self.y * self.y;

    item print(self: Point): unit = printString(
        "Point { x = " + self.x.toString() + ", y = " + self.y.toString() + " } (length: " + self.length().toString() + ")"
    );
};

val origin = Point.origin();
val offset: Point = .{ x = 3, y = 6 };
val other_point = origin.movedBy(offset);
other_point.invert();
other_point.print();
```

## Start here

- [Matcha goals](./docs/goals.md) explains why the language exists, what it optimizes for, and what it intentionally does not try to be.
- [learning-matcha.mt](./matcha-compiler/examples/learning-matcha.mt) is a runnable tour of the current language surface.

> [!WARNING]
> Matcha is early-stage software. The language, compiler, runtime, CLI, and tooling may all change significantly.

## Quick try on macOS

### 1. Optional: install the VS Code extension

Install [Matcha Language Support](https://marketplace.visualstudio.com/items?itemName=mario-nowak.matcha-lang) from the Visual Studio Marketplace for syntax highlighting and basic editor integration.

### 2. Install the compiler

```sh
brew tap mario-nowak/tap
brew install mario-nowak/tap/matcha-lang
```

If `clang` is not available yet, install Xcode Command Line Tools:

```sh
xcode-select --install
```

### 3. Clone the repository and run an example

```sh
git clone https://github.com/mario-nowak/matcha.git
cd matcha/matcha-compiler
matcha run examples/learning-matcha.mt
```

For full setup, source builds, and compiler usage, see [`matcha-compiler/README.md`](./matcha-compiler/README.md).

## Current status

Today, the compiler can already handle a meaningful core language, including:

- `val` and `var`
- `int`, `boolean`, and `string`
- arrays with indexing, `append`, and `length`
- structures with fields, methods, and type functions
- `if`, `while`, `for`, `loop`, and `match`
- built-ins such as `printInt`, `printString`, `readFile`, `readLine`, and `getArguments`
- LLVM IR emission and native binary generation

The documented compiler setup is currently macOS-first.

## What is in this repository?

This repository is a monorepo with two main parts:

- [`matcha-compiler/`](./matcha-compiler) — the compiler, runtime, CLI, tests, and example programs
- [`tooling/ide-extensions/vs-code-extension/`](./tooling/ide-extensions/vs-code-extension) — a VS Code extension with syntax highlighting and basic editor support

## Monorepo layout

```text
.
├── matcha-compiler/                     # compiler, runtime, examples, tests
├── tooling/ide-extensions/
│   └── vs-code-extension/              # VS Code extension
└── assets/                             # logos and project assets
```

## Suggested starting points

- [`matcha-compiler/README.md`](./matcha-compiler/README.md) — compiler setup, commands, and development workflow
- [`matcha-compiler/examples/learning-matcha.mt`](./matcha-compiler/examples/learning-matcha.mt) — guided tour of the currently implemented language
- [`matcha-compiler/examples/aoc-2024-01.mt`](./matcha-compiler/examples/aoc-2024-01.mt) — Advent of Code-style parsing and array processing
- [`matcha-compiler/examples/customer-import-audit.mt`](./matcha-compiler/examples/customer-import-audit.mt) — a more domain-shaped example using structures and `match`
- [`tooling/ide-extensions/vs-code-extension/README.md`](./tooling/ide-extensions/vs-code-extension/README.md) — VS Code extension documentation
