# Testing conventions

Tests in Matcha should optimize for clarity, focus, and useful failures. A reader should quickly see the setup, the behavior being exercised, and the expected outcome.

## Structure a test

A test has three parts. The nested `pub` structs hold the context, the test name states the expected behavior, and the body follows Arrange -> Act -> Assert.

```zig
pub const NodeTypeAnalyzer = struct {
    pub const analyzeProgram = struct {
        pub const unions = struct {
            pub const qualified_cases = struct {
                test "rejects a payload case when it is not called" {
                    const source =
                        \\item Result = union { None, Some: int };
                        \\val result = Result.Some;
                    ;
                    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
                    defer arena.deinit();
                    const fixture = try setupNodeTypeAnalyzerFixture(&arena, source);

                    const result = fixture.node_type_analyzer.analyzeProgram(&fixture.resolved_program, fixture.exit_behavior_by_node_id);

                    try expect(result).toBeError(error.DiagnosticsEmitted);
                    try expect(fixture.diagnostic_store.items()).toMatch(.{
                        .{ .message = "union constructors can only be called" },
                    });
                }
            };
        };
    };
};
```

### Context

- The first level names the subject or component. The second level names the operation. Both mirror the real code names, for example `NodeTypeAnalyzer` and `analyzeProgram`. This intentionally deviates from Zig's snake_case style for namespace structs.
- Below the operation, add behavior groups in snake_case, for example `unions` or `qualified_cases`. Nest them as deep as the grouping stays meaningful.
- Tests can sit at any level. A scope does not need sub-scopes.

### Name

- Name each test `<expected behavior> [when <condition>]`. Do not add `it` literally or force a `when` clause when the behavior is already clear.
- Names should explain what behavior regressed, not merely repeat a function name. Keep them specific without adding unnecessary detail.

### Body

- Separate Arrange, Act, and Assert with exactly one blank line. Whitespace makes the phases visible. Do not add `// Arrange`, `// Act`, or `// Assert` comments.
- Avoid blank lines within a phase. Small tests can omit a phase. Do not add artificial setup to preserve the structure.
- Prefer one conceptual Act per test. This need not mean exactly one function call, but the operation under test should be obvious.

### Registration

Zig only analyzes a nested `test` when something references its struct. A missed reference skips the tests silently, so follow both rules:

1. Mark every scope struct `pub`. The registration only sees `pub` declarations.
2. Register the file in `src/compiler/tests.zig` with `referenceAllTestsRecursive(@import("..."))`. A plain `_ = @import("...")` skips all nested tests.

`referenceAllTestsRecursive()` exists only in `src/compiler/tests.zig`. The CLI tests (`src/cli/module.zig`) and the e2e tests (`tests/e2e/tests.zig`) have their own test roots. Add the helper to a root before its files use nested scopes.

### Filtering

Zig reports a nested test with its full dotted path:

```text
semantic_analysis.type_checking.node_type_analyzer.test.NodeTypeAnalyzer.analyzeProgram.unions.qualified_cases.test.rejects a payload case when it is not called
```

`-Dtest-filter` keeps every test whose full name contains the filter text. It is case-sensitive.

- One scope: `-Dtest-filter=unions.qualified_cases`
- A scope and a title prefix: `-Dtest-filter=qualified_cases.test.rejects`
- Several scopes: repeat the option. A test runs when it matches any filter.

## Test one behavior

Each test should describe one behavioral scenario. Multiple assertions are appropriate when they verify different aspects of that behavior.

Do not combine independent scenarios merely because they exercise the same function or feature. Several examples can share a test when they demonstrate one compact rule.

## Keep tests locally understandable

Keep meaningful inputs, state, and expectations visible in the test. A reader should not need to follow a chain of helpers to understand the scenario.

Use helpers to hide mechanical details such as construction, allocation, resource management, or token collection. Some repeated setup is preferable to an abstraction that hides meaning.

Use the smallest fixture that clearly expresses the scenario. Include larger or more realistic context only when that context matters to the behavior.

## Assert only what matters

Assert the contract under test, not every property of the result. Every asserted property should contribute to proving the behavior named by the test.

Prefer narrow assertions when only part of a value matters. This reduces failures caused by unrelated changes.

## Prefer declarative expectations

Describe expected structures directly instead of manually inspecting each part. Prefer `expect(actual).toMatch(expected)` when it expresses the intent clearly.

```zig
try expect(actual).toMatch(.{
    .enabled = true,
});
```

`toMatch()` supports partial structural matching:

- For structs, only explicitly provided fields are checked. Omitted fields are intentionally ignored, including within nested structs.
- For non-string slices, tuple expectations describe the complete sequence, including its length and order. Each element is matched recursively.
- Strings are compared by their contents.

Use partial matching to express relevant structure, not whole-value snapshots without a reason. Use `std.testing` or imperative assertions when they are clearer.

## Test observable behavior

Test behavior exposed by the unit, not its internal implementation steps. Choose the narrowest testing level that naturally expresses the behavior.

Use focused unit tests for local behavior. Use integration or end-to-end tests when the behavior depends on interactions across components.

## Keep failures useful and helpers lightweight

Tests are debugging tools. Prefer assertions that clearly identify what differed and where. Concise test code is useful only when failures remain understandable.

Matcha builds on Zig's native testing facilities. Add small helpers when recurring tests show a need for clearer setup, assertions, or failure output.


## Review checklist

- Is the test inside nested scopes for its subject, operation, and behavior group?
- Does the name state the expected behavior, with a `when` clause only when useful, and without repeating a scope?
- Is every scope struct `pub`, and is the file registered with `referenceAllTestsRecursive`?
- Does the test cover one behavioral scenario?
- Are Arrange, Act, and Assert clear and separated by one blank line?
- Is there one conceptual Act?
- Are meaningful inputs and expectations visible locally?
- Does the fixture contain only relevant context?
- Does every asserted property matter to the behavior under test?
- Is the expectation expressed as directly as possible?
- Would a failure clearly communicate what behavior broke?

These conventions support readability, not formatting for its own sake. Apply them conservatively when a mechanical rewrite would make a test harder to understand.
