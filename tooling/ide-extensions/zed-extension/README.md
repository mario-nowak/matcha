# Matcha for Zed

Syntax highlighting, bracket matching, and auto-indent for Matcha in Zed.

The grammar lives in `tooling/tree-sitter-matcha`. It is token-level: it knows tokens and bracket nesting, not Matcha's syntax. Highlighting context comes from neighboring tokens in `languages/matcha/highlights.scm`.

## Local install

1. Commit and push the grammar (`tooling/tree-sitter-matcha`, including the generated `src/`).
2. Set `rev` in `extension.toml` to that commit SHA. Zed fetches the grammar from git at this revision.
3. In Zed, run `zed: install dev extension` and select this directory.

To try uncommitted grammar changes, point `repository` at `file:///<path-to-matcha-checkout>` and use a local commit SHA for `rev`.

## Changing the grammar

1. Edit `tooling/tree-sitter-matcha/grammar.js`.
2. Run `tree-sitter generate` in `tooling/tree-sitter-matcha` and commit the regenerated `src/`.
3. Update `rev` in `extension.toml`.

Check a query against a file with `tree-sitter query <query.scm> <file.mt>` from `tooling/tree-sitter-matcha`.
