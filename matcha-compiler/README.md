# matcha-compiler

Local macOS setup:

1. Install LLVM 20 with Homebrew:

```sh
brew install llvm@20 bdw-gc
```

2. Trust this repository's `mise` configuration:

```sh
mise trust
```

3. Install the tools declared in `.mise.toml`:

```sh
mise install
```

After that, `mise` will provide `zig`, and the repository's `.mise.toml` will prepend Homebrew's `llvm@20` binaries to `PATH` so the `jit` task can find `lli`.

Useful commands:

```sh
mise tasks run build
mise tasks run test
mise tasks run jit -- path/to/file.mt
mise tasks run build-compiler
mise tasks run emit -- path/to/file.mt
mise tasks run compile -- path/to/file.mt
./path/to/file
```
