# Matcha Language Support

Syntax highlighting and basic editor support for the Matcha programming language.

## Features

- Syntax highlighting for current Matcha keywords, declarations, types, literals, and operators
- Line comments with `//`
- Bracket matching and auto-closing for `()`, `[]`, `{}`, and strings
- File associations for `.mt` and `.matcha`
- Custom file icon for Matcha source files

## Status

This extension tracks Matcha `v0.1.0` and is still experimental.

Current scope:
- TextMate grammar-based syntax highlighting
- Language configuration only

Not included yet:
- Diagnostics
- Formatting
- Go to definition
- Semantic tokens
- Debugging support

## Installation

### From a packaged VSIX

```sh
code --install-extension matcha-lang-0.1.0.vsix
```

## Development

Package locally:

```sh
npx @vscode/vsce package
```

Install locally after packaging:

```sh
code --install-extension matcha-lang-0.1.0.vsix
```

## Repository

Monorepo path:
- `tooling/ide-extensions/vs-code-extension`

Compiler examples for manual testing:
- `matcha-compiler/examples/learning-matcha.mt`
- `matcha-compiler/examples/aoc-2024-01.mt`
- `matcha-compiler/examples/customer-import-audit.mt`
