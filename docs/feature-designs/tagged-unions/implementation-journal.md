# Union implementation journal

- At first, implementing unions seemed manageable.
- Turns out it is way more complex than I thought.
- My first [implementation plan](./implementation-plan.md) (as of writing this journal) seemed pretty sensible

- Turns out, unions touch every phase of the compiler at once
    - two grammars in the parser (expression + pattern grammar)
    - binding in name resolution
    - contextual construction with implicit member expression in the type checker
    - exhaustiveness
    - lowering
    - branch-on-tag in codegen

- "Right now" (as of this commit hash) I'm running into this issue:
- Say we have something innocent looking like this:
```matcha
item Result = union {
    None,
    Some(int),
};
val value1: Result = .None;
val value2: Result = .Some(3);
val value3 = Result.None;
val value4 = Result.Some(3);
```
- At the AST-level
    - several questions come up, like
        - what is `.Some(3)` exactly?
        - what is `Result.Some(3)` exactly?
        - what is `.None` exactly?
        - what is `Result.None` exactly?
    - I initially decided to go with the following direction:
        - `Result.None` is a regular member expression
        - `.None` is an "implicit member expression"
            - Because the base of the member expression is implied due to the type context
        - `Result.Some(3)` is a call expression where the callee is a member expression
        - `.Some(3)` is a call expression where the base is an implicit member expression
    - This design initially felt very good because it is compounding two abstractions (implicit member expression and call expressions) into a new thing
- But this raises some questions at the type-checking level:
    - The type of `Result.Some(3)` should be `Result`. That is obvious
    - But `Result.Some` is also node in the AST. What is its type?
        - Is it also `Result`?
        - That seems a bit disingenuous because `Result.Some` cannot exist on its own in the type system
        - Maybe `Result.Some` is a function type that accepts a `int` and returns a `Result`?
    - The type of `Result.None` exactly?
        - Is it `Result`?
        - Keep in mind that `Result.None(unit)` is actually the proper version of that expression.
    - What is the type of `.None` exactly?
    - Etc. etc.

- The way I see it, I have three options:
    - case reference is typed as the union
        - this was/is my initial implementation as of writing this journal
    - case reference is typed as a function
        - is is conceptually probably the most honest option and my current favorite candidate
        - `Result.Some` and `.Some` would have the same type: `(int) -> Result`
        - `.None` should conceptually be syntactic sugar for `Result.None(unit)`
            - This creates the following special case:
            - `Result.None` and `.None` by themselves have the type `Result`
            - When used as the callee of a call expression, e.g. `.None(unit)`
                - The call expression allows 
        - `Result.Some` could be used in other contexts such as:
            - `val results = some_array.map(.Some)`
        - But it creates new questions:
            - What happens here:
                - `val x = Result.Some;`?
            - This made me realize that this is also a smell
    - dedicated case-construction node in the AST
        - This is the option I like least because it adds a new concept just for the implicit member version
        - And for the qualified construction case I would have create special handling would have to be very similar to the current implementation
        - Defeating the purpose of it

- Actually, there is a fourth way saner option that I just thought about
    - `Result.Some` is not a function, it is a `UnionConstructor`
    - And `UnionConstructor` and `Function` are both callable
    - But what happens here: `val x: Result = .None`?
        - In contexts where a union constructor is not in a callable position and the payload is of type unit, I type it as the Union
        - But this means need to know in which position a node is being processed
- And I also realized that match currently allows this:
```matcha
val x = SomeStructure;
val y = SomeFunction;
```
- Which it should not really allow at this point
- Which means I need to keep track of which position the current node is. Function and Union Constructors should only be used in callee contexts.
    - Like only here: `SomeFunction()` and not even here: `(if cond { FunctionA } else { FunctionB });`
- And Union and Structure identifiers are never allowed except for Type Annotations and direct member accesses
- So the parent has an expectation to one child and this expectation only holds for one edge in the AST
- This expectation is not inherited by other children
- Right now matcha has the concept of a TypeCheckingEnvironment which every child node inherits unless explicitly overridden
- But this is different, this is more of an expectation that a parent node has on it's immediate child
- So we need a new concept.
- Instead of an inheritance-by-default environment we also need an override-by-default set of expectations
- `ParentExpectation`
    - Which needs to store in which position we expect to see a certain type
    - For example functions and union constructors only as direct callees, and nowhere else
- Which stores the immediate expectations that a parent has on it's children
- The current `TypeCheckingEnvironment` encodes
    - `exit_behavior_by_node_id`
        - function is irrelevant for now
    - `context: ValidationContext`
        - In which context this node is being validated
            - statement or value
        - But this name is really poor
        - This is actually more of the `Role` of a node
            - Nodes can either be a statement or an expression
    - `contextual_type_id: ?TypeId`
        - The expected type of the node given the current environment
        - e.g. `val myArray: int[] = [1, 2, 3];` requires the right hand side needs to have the `int[]` type
    - `function_return_type_id: ?TypeId`
        - the expected return type of a function
- And also notice something:
    - the `context` and `contextual_type` actually have an override by default behavior
    - Every node sets them themselves except for if and match expressions
- And like I said we need to store in what position a node is used for the callee check anyway
- So this is a natural consequence for the split:
- `TypeCheckingEnvironment`
    - `exit_behavior_by_node_id`
    - `function_return_type_id`
- `ParentExpectation`
    - `node_role: NodeRole`
        - `Statement`
        - `Expression`
            - `Value`
            - `Callee`
    - `node_type_id: TypeId`
- This way we can manage the lifetimes of these properties differently during the traversal through the AST

- On lowering unions
    - I plan to lower them by representing unions almost exactly the same way as structs
    - Each case of a union would receive its own type.
    - By being pointers to a llvm struct where the first field is the case index
    - So something like:
    ```matcha
    item MaybeInt = union {
        .None, // <- implicitly of type unit
        .Some(int),
    };
    ```
    - would become:
    ```llvm
    %MaybeInt.None = type { i8 }
    %MaybeInt.Some = type { i8, i64 }
    ```
    - conceptually

---

I asked AI to review my compiler and it identified 55!!! potential issues:
> "I asked for praise and got 55 bugs"

```
Here are the issues, grouped by area. Each has a title and a short body. Nothing is created yet. Issue #25 (atomic allocation) already exists, so it's left out.

Correctness

1. Make and and or short-circuit. Both operands are always evaluated, so false and side() calls side(), and i < a.length and a[i] == x panics.
2. Array store is lost when the right side appends to the same array. arr[0] = grow(arr) stores into the old buffer when grow appends. The element address is computed before the right side runs.
3. Check integer division by zero. / emits a raw sdiv, which is undefined behavior for zero and for INT_MIN / -1.
4. Reject integer literals that are too big. 99999999999999999999 silently compiles to 0.

Compiler crashes

5. Crash when a function body ends in a loop. item f(): int = { loop { return 1; } }; panics in expectRegister.
6. leave counts as fall-through in exit analysis. loop { leave; return 1; } is accepted and then crashes codegen. loop { if c { return 1; } } is rejected, although it can only exit by returning.
7. Crash when an item has a builtin's name. item printInt(value: int): unit = unit; panics with "Symbol 2 is already finalized".
8. Crash on empty structure literals. val p: Point = .{}; panics with "index out of bounds" instead of reporting the missing fields.
9. Empty array literal accepts any expected type. val x: int = []; type-checks and then crashes codegen.

Type system and name resolution

10. Add a never type for diverging branches. if c { return 1; } else { 2 } fails with "then: unit, else: int".
11. For-in bindings skip name validation. for x in xs shadows an outer x, and for printString in xs is accepted.
12. Reserve builtin type names. item int = structure {...}; is accepted but can never be used.
13. Misleading error for module values used in functions. A top-level val g used inside a function reports "undefined identifier".
14. Detect duplicate negative match arms. -1 => ..., -1 => ... isn't reported as a duplicate.
15. Decide whether a val structure's fields can be assigned. val p = ...; p.x = 2; is accepted. Document it or reject it.
16. == doesn't pass an expected type to its right operand. event == .KeyPress("Enter") can't resolve the implicit case.

Parser and diagnostics

17. Require commas between call arguments. f(1 2) and f(,,1,) compile.
18. Allow only one else in a match, and only last. A second else silently replaces the first. An else in the middle is accepted.
19. Diagnostic carets are one column too far left. Every rendered error shows the caret under the space before the problem.
20. Lexer errors are reported twice. x @; prints "unrecognized character" twice, because parser lookahead reports the same error again.
21. Empty blocks are rejected. { } and loop {} fail with "expected expression".
22. Inconsistent semicolon rules after block statements. A nested block needs ; and a top-level one doesn't. if {} else {} needs ; and if {} doesn't.
23. Add a pattern node for match arms. Arms are parsed as plain expressions, so payload bindings like .Some(x) can't work.
24. Map binary operators in one place. Binding power and the token-to-operator mapping are separate switches, and the second one ends in unreachable.
25. Float literals give a confusing error. 1.5 fails with "expected member name after '.'". Either support floats or remove RealLiteral.

Language and runtime

26. readLine can't signal end of input. It returns "" at EOF, so a read loop never ends.
27. toInt accepts non-decimal syntax. "1_000".toInt() gives 1000, and "+5".toInt() gives 5.
28. Runtime errors have no source location. "failed to parse int" doesn't show where or which value.
29. Add the % operator. There's no remainder operator.
30. Use one member separator. Structure fields use ;, while cases, literals, arms and parameters use ,.
31. Docs don't match the syntax. goals.md and the union journal show syntax the parser doesn't accept.

Unions

32. Union method calls record no member access. CallLowerer will hit unreachable once unions are lowered. Not verified yet.
33. Union case names and types live in two places. Names are in the symbol, types are in UnionType, and they're matched by index.

CLI and toolchain

34. Errors outside diagnostics exit silently. A missing input file or a clang failure exits with code 1 and no message.
35. matcha build can overwrite the source file. Without a .mt extension, the output path equals the input path.
36. matcha run hides crashes. A segfault in the program shows only exit code 1.
37. Unknown commands show NameNotPartOfEnum. Print a usage hint instead.
38. The runtime library path is relative to the executable. A copied matcha binary can't find libmatcha_runtime.a.
39. The target triple uses the full macOS version. Binaries built on macOS 26.6.2 may not run on older macOS versions.
40. clang and Homebrew are hardcoded. There's no override for the compiler, and brew --prefix runs on every build.
41. Build the runtime as PIC. Linux needs -no-pie because the runtime library isn't position-independent.

Codegen internals

42. Each lowerer has its own AST walker. Every new node kind needs 8 edits.
43. Emission re-derives lowering decisions. Unit element checks, boolean match exhaustiveness and the allocation strategy are decided in the emitters.
44. %Array field indices are hardcoded. About 6 GEPs use 0 and 2 directly.
45. Allocation calls bypass RuntimeCallEmitter. @matcha_allocate is written as a raw string in aggregates.zig.
46. Allocation results are never checked for null. Out of memory leads to stores through null.
47. Runtime output ignores short writes and isn't buffered. Output to a pipe can be cut off, and printing is slow.
48. readLine makes one syscall per byte.

Semantic data design

49. Remove runtime_representation_by_node_id. It's derived from the node types and the per-type table.
50. Intern function types. Every method access creates a new function type.

Front-end internals

51. Out of memory crashes the parser. About 40 catch unreachable sites ignore error.OutOfMemory.
52. peek() copies string literals every time. Each lookahead decodes and allocates the string again.

Tests

53. Validate generated LLVM in tests. Run llvm-as or opt -verify on the full-module test outputs.
54. Add unit tests for the runtime. split, trim, toInt and append_slot have none.
55. Add parser error and renderer tests. Almost no error paths are tested, and the diagnostic renderer has no tests.

That's 55 issues. Some are decisions rather than bugs, for example 15, 25, 29 and 30. Tell me which ones to create, or say "all".
```

now not all of them are real issues. But a lot of them are.

---

- I tried to implement union lowering after all the frontend and semantic analysis work but I realized that match expressions will be the main consumer for unions and without that consumer it is really difficult to think about how to lower them properly for that consumer
- Therefore I'm not switching to implementing the frontend and semantic analysis of that first before working on the lowering 
- I probably need a separate pattern AST for patterns only
- and in the match expression node's arm I would rename the `pattern_or_condition` to just `pattern` and type it as a `PatternNode`
- A `PatternNode` would be a specific sub-AST just for expression patterns
    - Right now I think it should contain
        - `else`
        - string literals
        - int literals
        - boolean literals
        - member expression + optional capture syntax
        - implicit member expression + optional capture syntax
    - Ideally I could add a dedicated parser just for that and add it as a dependency of the current parser
    - That could help not bloat the existing parser all too much
    - `PatternParser` with a `parsePattern` method
    - Name resolution would bind the identifier in the capture to the arm expression
    - And then thread these changes through the compiler, this should not have any changes on the lowering
- And I want to split `MatchExpression` into two ones
    - `MatchExpression` where the left hand sides of the arms are patterns and
    - `SubjectlessMatchExpression` where the left hand sides of the arms are expressions

---

- Union equality is decided but deferred: one compiler-generated equality function per union type, for example `@matcha.union.Maybe.synthetic_function.equal(ptr, ptr)` (see the IR naming plan below), emitted only for compared unions and the unions reachable through their payloads. Inline comparisons would need hand-built loops for recursive and mutually recursive unions, while a function just calls itself. It is the first compiler-generated function, so it needs new machinery, and `match` covers most uses until then.

---

# Cleanups for later

- Merge the five identical error sets (`LexError`, `ParseError`, `ControlFlowValidationError`, `NameResolutionError`, `TypeError`) into one `CompileError = error{DiagnosticsEmitted} || std.mem.Allocator.Error` in the `diagnostics` module.
- Switch all lowerers to the arena pattern of `UnionLayoutLowerer`: `lower()` returns a freshly allocated result, the lowerer keeps no state, and `deinit()`, `clearLayouts()` and all frees go away (the allocator is named `arena`).
- Replace `catch unreachable` on allocations with `try`, so `error.OutOfMemory` propagates through `CompileError` instead of being undefined behavior in ReleaseFast (review item 51).
- Delete `getTypeIdFromResolvedTypeReference()` and the unused `getLlvmIrTypeFromResolvedTypeReference()` in `llvm_type.zig`: they redo the type checker's reference-to-type translation in codegen. The renderers should read `StructureType.fields[i].type_id` and `UnionType.cases[i].type_id` instead.
- Emit union payloads and structure field values before the allocation, not after it, so an early exit in a payload or field expression doesn't leave a wasted allocation behind. Fixed while lowering unions, for array literal elements too.
- The renaming of the codegen value and slot concepts and of the labels moved into the IR naming plan below.
- Learn about optimization flags. `linker.zig` calls `clang` without `-O`, so it compiles at `-O0` and `mem2reg` never runs. Every `alloca`/`store`/`load` of a binding stays in the binary as a real stack access. Consider a `--release` flag on `matcha build` that passes `-O2`.
- Load the case index of a union match subject once, not again in every arm. Today `UnionCaseIndexComparison` loads it for each comparison. The LLVM optimizer removes the extra loads at `-O1` and above.
- Construct unit cases like `Maybe.None` once, as one global constant per case, instead of allocating on every use.
- Allocate case structures without pointers, for example a unit case or an `int` payload, with `matcha_allocate_atomic`, so the garbage collector does not scan them. This belongs with the atomic allocation work in issue #25.
- Split `DecisionConstruct` in `control_flow.zig` into a pattern match construct and a condition chain construct. Today one construct serves both, so it allows a construct without a subject but with pattern arms. Pattern matching will grow apart from the subjectless match, like the planned split of `MatchExpression` above.
- Keep the case names and the case types of a union in one place (review item 33). The names are in the union symbol and the types are in `UnionType`, matched by index. `UnionLayoutLowerer` reads the names from the symbol.

---

# IR naming plan

- Goal: an IR name only changes when the related source changes. Global counters (symbol ids, node ids) break this, because one new builtin or one new parser node renames unrelated code. Example: registering the builtins before the module items (review item 7) shifts every symbol id by 5 and breaks 30 IR tests.
- Separator is `.`, not `__`. Identifiers can contain `__`, so `__` names are ambiguous: structure `X` with function `b__function__c` and structure `X__function__b` with function `c` both give `matcha_structure__X__function__b__function__c`. Identifiers can never contain `.`, and LLVM accepts `.` in unquoted names.
- Sigils: `@` is a global name (functions, global constants). `%` is a local name (values, parameters, labels) or a named type. Types have their own namespace.

## Global names

- `matcha` followed by pairs of `<kind>.<name>`. The kinds are a fixed list, so a user name is never read as a kind. A modifier joins its kind with `_` (`synthetic_function`) to keep the pairs regular.

| What | Name |
|---|---|
| top-level function | `@matcha.function.add` |
| structure type | `%matcha.structure.Point` |
| structure function | `@matcha.structure.Point.function.origin` |
| union case type | `%matcha.union.Maybe.case.Some` |
| union function | `@matcha.union.Result.function.fromNumber` |
| compiler-generated function | `@matcha.union.Maybe.synthetic_function.equal` |
| string literal | `@matcha.string_literal.<n>` |
| builtin function | `@matcha.compiler_module.builtin.function.printInt` |
| builtin method | `@matcha.compiler_module.builtin.type.string.method.trim`, `@matcha.compiler_module.builtin.type.int.method.toString` |
| builtin type | `%matcha.compiler_module.builtin.type.string`, `%matcha.compiler_module.builtin.type.array` |
| runtime internal | `@matcha.compiler_module.runtime.function.allocate` |

- `function` marks a user-defined function, `synthetic_function` a compiler-generated one, so a user function `equal` cannot clash with the generated one.
- No case index in case type names: case names are unique within a union.
- Builtins and runtime internals live in compiler-provided modules. The kind `compiler_module` cannot clash with a user module, because user modules use the kind `module`. So a user file `builtin.mt` stays allowed and no name is reserved.
    - Not `internal_module`: `internal` is an LLVM linkage and a common visibility keyword, and builtins are public.
    - Not `$builtin` or `module..builtin`: `$` is unwanted, and an empty name breaks the pairs.
- The runtime exports its functions with `@export(&printInt, .{ .name = runtime_symbols.builtin_print_int_function_name })` instead of `export fn matcha_print_int`. The runtime imports the `runtime_symbols` module, so the compiler and the runtime share one spelling of every name.
- Runtime internal names translate the old names to camel case: `matcha_string_concatenate` becomes `stringConcatenate`, `matcha_init_arguments` becomes `initArguments`.
- The `runtime_symbols` constants say what they name: `builtin_print_int_function_name`, `builtin_string_trim_method_name`, `runtime_allocate_function_name`. The Zig functions in the runtime use the same camel case names as the IR, for example `fn stringConcatenate`.
- `@main` stays. Its parameters become `%parameter.argc` and `%parameter.argv`.

## Modules

- Modules prepend pairs: `@matcha.module.json.module.parser.function.parse`. Names in the entry module do not change, so adding modules renames nothing that exists today.
- Open decisions for the modules design:
    - Module names must be identifiers. A rule is needed for file names like `json-parser.mt`.
    - Whether the entry module gets a pair (`module.main`) or none.
    - One LLVM module per program or per Matcha module. Per Matcha module, string literals need `private` linkage or a module pair.

## Local names

- Every local name starts with a fixed category, so no raw user name appears as a local name. No leading `.` is needed.

| What | Name | Counter |
|---|---|---|
| value | `%value.<n>` | per function, from 0 |
| binding address (`val`, `var`, parameter, `for` item, payload binding) | `%address.binding.<name>.<n>` | per function and name, from 0, always present |
| synthetic address (`for` index, runtime call result) | `%address.synthetic.<n>` | per function, from 0 |
| parameter | `%parameter.<name>` | none, parameter names are unique |

- Code renames to match: `Register` becomes `Value`, `Storage` becomes `Address` (`generateRegister()`, `EmissionResult.register`, `expectRegister()`, `storage_by_symbol_id`).

## Labels

- `<construct>.<n>.<role>`, where `<n>` counts that construct per function, from 0. The same scheme for every control-flow construct:

| Construct | Labels |
|---|---|
| `if` | `if.0.then`, `if.0.else`, `if.0.end` |
| `match` | `match.0.arm.1`, `match.0.arm.1.condition`, `match.0.else`, `match.0.end` |
| subjectless `match` | the same roles with `subjectless_match` |
| `while` | `while.0.header`, `while.0.body`, `while.0.continue`, `while.0.exit` |
| `loop` | `loop.0.body`, `loop.0.exit` |
| `for in` | `for_in.0.header`, `for_in.0.body`, `for_in.0.continue`, `for_in.0.exit` |
| `and`, `or` | `and.0.right`, `and.0.end` |
| index bounds check | `index.0.ok`, `index.0.panic` |

- The role names still need a pass over `control_flow.zig`. Some differ today, for example `next` and `continue` versus `end`.

## Order

1. User-defined global names: the three layout lowerers and `StringLiteralPool`.
2. Review item 7: register the builtins before the module items. Harmless after step 1.
3. Builtin and runtime names: the runtime exports, `RuntimeSymbolRenderer` and the builtin types in `llvm_type.zig`.
4. Code renames only (`Register` to `Value`, `Storage` to `Address`). No IR change.
5. Local value, address and parameter names.
6. Labels.

- Proof that a rename is pure: a script maps the old names to the new names in the old test expectations, and the result must equal the new expectations. Running `llvm-as` on the test outputs (review item 53) also catches invalid names.
