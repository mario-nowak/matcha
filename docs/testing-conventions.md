# Testing conventions

Tests in Matcha should optimize for clarity, focus, and useful failures. A reader should quickly see the setup, the behavior being exercised, and the expected outcome.

## Arrange, Act, Assert

Follow Arrange -> Act -> Assert. Separate the phases with exactly one blank line.

```zig
test "Parser > parse: rejects a union when it has no cases" {
    const source = "item Empty = union {};";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const parser_pipeline = try setupParserPipeline(&arena, source);

    const result = parser_pipeline.parser.parse();

    try std.testing.expectError(error.DiagnosticsEmitted, result);
    try expect(parser_pipeline.diagnostic_store.items()).toMatch(.{
        .{ .message = "union definitions must have at least one case" },
    });
}
```

Whitespace makes the phases visible. Do not add `// Arrange`, `// Act`, or `// Assert` comments.

Avoid blank lines within a phase. Small tests can omit a phase. Do not add artificial setup to preserve the structure.

Prefer one conceptual Act per test. This need not mean exactly one function call, but the operation under test should be obvious.

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

## Name tests by behavior

Use this structure for test names:

```text
<describe> > <describe>: <it>
```

The first section names the subject or component. The second names the operation or behavior group. The final section states the expected behavior.

Add an optional `when` clause to describe the condition under which the behavior occurs:

```text
<subject> > <operation>: <expected behavior> [when <condition>]
```

Examples:

```zig
test "Parser > parse: parses union definitions" { ... }
test "Parser > parse: rejects a union when it has no cases" { ... }
test "Lexer > next: emits a diagnostic when a string is unterminated" { ... }
```

Use ` > ` between context levels and `: ` before the expected behavior. Do not add `it` literally or force a `when` clause when the behavior is already clear.

Names should explain what behavior regressed, not merely repeat a function name. Keep them specific without adding unnecessary detail.

## Test observable behavior

Test behavior exposed by the unit, not its internal implementation steps. Choose the narrowest testing level that naturally expresses the behavior.

Use focused unit tests for local behavior. Use integration or end-to-end tests when the behavior depends on interactions across components.

## Keep failures useful and helpers lightweight

Tests are debugging tools. Prefer assertions that clearly identify what differed and where. Concise test code is useful only when failures remain understandable.

Matcha builds on Zig's native testing facilities. Add small helpers when recurring tests show a need for clearer setup, assertions, or failure output.


## Review checklist

- Does the name follow `Subject > operation: behavior`, with a `when` clause only when useful?
- Does the test cover one behavioral scenario?
- Are Arrange, Act, and Assert clear and separated by one blank line?
- Is there one conceptual Act?
- Are meaningful inputs and expectations visible locally?
- Does the fixture contain only relevant context?
- Does every asserted property matter to the behavior under test?
- Is the expectation expressed as directly as possible?
- Would a failure clearly communicate what behavior broke?

These conventions support readability, not formatting for its own sake. Apply them conservatively when a mechanical rewrite would make a test harder to understand.
