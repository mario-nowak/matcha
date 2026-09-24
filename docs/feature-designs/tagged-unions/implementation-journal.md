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