---
author: claude
status: draft
---

# Concurrency proposal

## AI Generated

Ideas under discussion. Nothing here is decided.

- No function coloring: no `async` or `await`. Blocking calls park the current task cheaply.
- `spawn` as a builtin function that takes a closure and returns a `Task<T>`.
- Tasks that cannot outlive the function that spawned them, with an explicit owner object for long-lived tasks.
- Every task joined, so that task errors cannot be lost.
- A rule for what may cross between tasks: values always, identity objects only without `var` fields.
- A small first version: `spawn`, `join`, and a `Mutex`. Channels and `select` later.
- Runtime: many tasks on few OS threads, large virtual stacks per task, Boehm GC thread support.
- Goal: Go's convenience without leaked goroutines, data races on values, or lost task errors.
