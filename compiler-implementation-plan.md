# Compiler Implementation Plan (MVP v0)

This document outlines the roadmap for extending the current compiler into the Matcha MVP v0. The implementation follows a **Vertical Slice** strategy, but first establishes a robust compiler architecture (Rich AST + Semantic Analysis).

## Architecture Overview

The compiler pipeline will be refactored to:
1.  **Lexer**: Source -> Tokens
2.  **Parser**: Tokens -> **Rich AST** (`ast.zig`)
3.  **Semantic Analysis (Sema)**: Rich AST -> **Typed AST** (`sema.zig`)
    *   *Responsibilities*: Name resolution, Type checking, Type inference.
4.  **Emitter**: Typed AST -> LLVM IR (`llvm_ir_emitter.zig`)

---

## Slice 1: Architecture Foundation & Block Expressions
**Goal:** Establish the new pipeline and implement Block Expressions `{ ... }`.

*   **Example:**
    ```matcha
    {
        val x = 1;
        val y = 2;
        x + y
    }
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `LeftBrace` (`{`) and `RightBrace` (`}`) tokens.
2.  **AST (`ast.zig`)**:
    *   Create `Node` union to replace `SExpression`.
    *   Add variants: `Integer`, `Identifier`, `BinaryOp`, `LetBinding`, `Block`.
3.  **Parser**:
    *   Update to return `Node`.
    *   Implement `parseBlock()`: Parse statements into `Node.Block`.
4.  **Sema (`sema.zig`)**:
    *   Create `SymbolTable` (Scope) to map names to Types.
    *   Implement `checkBlock()`: Push new scope, check statements, pop scope.
    *   *Check*: Ensure variables used are defined in current or parent scope.
5.  **Emitter**:
    *   Update to consume `Node`.
    *   Emit blocks (result is the last expression).

## Slice 2: Booleans & `if` Expressions
**Goal:** Introduce branching and Type Checking.

*   **Example:**
    ```matcha
    if true { 10 } else { 20 }
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `true`, `false`, `if`, `else`, `==`, `!=`, `<`, `>`.
2.  **AST**:
    *   Add `Boolean`, `If` variants.
3.  **Parser**:
    *   Parse `if` expressions.
4.  **Sema**:
    *   *Check*: Condition must be of type `boolean`.
    *   *Check*: `then` and `else` branches must return compatible types.
5.  **Emitter**:
    *   Implement `icmp`, `br`, labels, and `phi` nodes.

## Slice 3: Mutable Variables (`var`)
**Goal:** Mutability constraints and Stack allocation.

*   **Example:**
    ```matcha
    var x = 0;
    x = x + 1;
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `var` keyword.
2.  **AST**:
    *   Add `VarDecl` (mutable) vs `LetDecl` (immutable).
    *   Add `Assignment` node (`x = y`).
3.  **Sema**:
    *   Update Symbol Table to track `is_mutable` flag.
    *   *Check*: Error if assigning to a variable declared with `val`.
    *   *Check*: Assignment value type matches variable type.
4.  **Emitter**:
    *   Use `alloca` for `var` (stack memory).
    *   Use `store`/`load` for mutable access.

## Slice 4: Loops (`loop` / `leave`)
**Goal:** Iteration and Control Flow checking.

*   **Example:**
    ```matcha
    loop {
        if x > 10 { leave x; }
    }
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `loop`, `leave`, `continue`.
2.  **AST**:
    *   Add `Loop`, `Leave`, `Continue` nodes.
3.  **Sema**:
    *   *Check*: `leave` is only used inside a loop.
    *   *Check*: All `leave` expressions in a loop return the same type.
4.  **Emitter**:
    *   Emit `br` to loop start/end labels.

## Slice 5: Functions
**Goal:** Reusable code and Type Signatures.

*   **Example:**
    ```matcha
    item add(a: int, b: int): int = a + b;
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `item`, `return`, `,`.
2.  **AST**:
    *   Add `FunctionDecl`, `Call` nodes.
3.  **Sema**:
    *   Register function names and signatures in global scope.
    *   *Check*: Call arguments match parameter types.
    *   *Check*: Function body returns declared return type.
4.  **Emitter**:
    *   Emit `define i32 @name(...)`.
    *   Emit `call`.

## Slice 6: Structures (Exact)
**Goal:** Custom data types and Field checking.

*   **Example:**
    ```matcha
    item Point = structure { x: int; y: int; };
    val p = Point { x = 1, y = 2 };
    p.x
    ```

### Implementation Steps
1.  **Lexer**:
    *   Add `structure`, `.`.
2.  **AST**:
    *   Add `StructDecl`, `StructInit`, `FieldAccess`.
3.  **Sema**:
    *   Register Struct types.
    *   *Check*: Initialization provides all fields with correct types.
    *   *Check*: Field access refers to existing fields.
4.  **Emitter**:
    *   Define LLVM types.
    *   Use `getelementptr` for access.

## Slice 7: Arrays
**Goal:** Dynamic lists.

*   **Example:** `val list = [1, 2]; list.push(3);`

### Implementation Steps
1.  **Lexer**: Add `[`, `]`.
2.  **AST**: Add `ArrayLit`, `IndexAccess`.
3.  **Sema**:
    *   Infer array type from elements (e.g., `Array<int>`).
    *   *Check*: All elements in literal are same type.
    *   *Check*: Index is `int`.
4.  **Emitter**:
    *   Implement Array struct `{ size, capacity, data* }`.
    *   Implement `push` (realloc) and access.

## Slice 8: Intrinsics (Standard Library)
**Goal:** IO and String processing.

*   **Example:** `Standard.io.readFile(...)`

### Implementation Steps
1.  **Sema**:
    *   Pre-populate Symbol Table with standard library functions (`readFile`, `split`, `toInt`).
2.  **Emitter**:
    *   Link against C standard library functions (`fopen`, `malloc`, `printf`).

---

## General Advice
*   **Test often**: Write a small `.matcha` file for each slice to verify it works.
*   **Debug LLVM**: Read the `emission.ll` file frequently to understand what your compiler is outputting.
*   **Refactor**: Your `SExpression` union will grow large. Don't be afraid to split it into specific `Statement` and `Expression` enums later if needed.