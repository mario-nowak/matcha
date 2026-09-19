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
        - `Result.None` and `.None` would have the tame type: `(unit) -> Result`
        - `.None` would simply be syntactic sugar for `Result.None(unit)`
        - `Result.Some` could be used in other contexts such as:
            - `val results = some_array.map(.Some)`
        - But it creates new questions:
            - What happens here:
                - `val x = Result.Some;`?
    - dedicated case-construction node in the AST
        - This is the option I like least because it adds a new concept just for the implicit member version
        - And for the qualified construction case I would have create special handling would have to be very similar to the current implementation
        - Defeating the purpose of it

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