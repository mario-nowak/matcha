# Matcha MVP v0 Specification (Advent of Code Edition)

This document defines the "Kernel" of Matcha—the smallest set of features necessary to solve the first three days of Advent of Code. It prioritizes the core philosophy (Match-driven, Structural) while deferring advanced features and syntactic sugar.

## 1. Goal
Implement a minimal version of Matcha capable of:
1.  Reading files and processing strings.
2.  Performing arithmetic and logic.
3.  Using dynamic arrays and loops.
4.  Defining and using structural data.

## 2. Essential Primitives & Types

*   **`int`**: 64-bit signed integers.
*   **`boolean`**: `true` / `false`.
*   **`string`**: Heap-allocated, immutable text.
*   **`Array<T>`**: Dynamic, heap-allocated arrays.
*   **`unit`**: The type of expressions that return no value (void).

## 3. Essential Data Modeling

For v0, we restrict data modeling to **Exact Structures** only.

*   **Definition**: `item Point = structure { x: int; y: int; };`
*   **Instantiation**: `val p = Point { x = 1, y = 2 };`
*   **Access**: `p.x`
*   **Constraint**: No "Shapes", "Contracts", or "Opaque" types yet. Structures must match exactly.

## 4. Essential Control Flow

### Core
*   **`match`**: The primary branching mechanism.
    *   Must support matching on literals (`1`, `"a"`, `true`).
    *   Must support the wildcard pattern (`_`).
    *   *Note:* Complex destructuring can be deferred if necessary, but basic literal matching is required.
*   **`loop`**: The primitive infinite loop.
    *   Must support `leave` (break) to exit the loop with a value.
    *   Must support `continue` to skip to the next iteration.
*   **`if`**: Basic conditional execution.

### Sugar (Transpiled to Core)
*   **`while (cond) { body }`** -> `loop { if !cond { leave; } body }`
*   **`for x in array`** -> `var i = 0; loop { if i >= arr.len leave; val x = arr[i]; body; i = i + 1; }`

## 5. Functions

*   **`item` functions**: Top-level, compile-time definitions.
    *   Syntax: `item add(a: int, b: int): int = a + b;`
*   **`val` functions**: Lambdas/Closures (essential for `map`/`filter`).
    *   Syntax: `val add = (a: int, b: int) => a + b;`

## 6. The "Standard Library" (Intrinsics)

These should be implemented as built-in intrinsics or simple wrappers to enable AoC solutions.

### IO
*   `Standard.io.readFile(path: string): string` - Reads an entire file into a string.
*   `Standard.console.log(msg: string): unit` - Prints to stdout.

### String
*   `.split(delimiter: string): Array<string>`
*   `.trim(): string`
*   `.toInt(): int` (Panic on failure for v0)
*   `.length(): int`

### Array
*   `.length`: int
*   `.push(item: T): unit`
*   `.get(index: int): T`

## 7. Core vs. Sugar Implementation Strategy

To accelerate development, distinguish between features requiring backend support (**Core**) and those handled by the frontend parser (**Sugar**).

### The Core (Backend / Interpreter)
1.  **Blocks & Scoping**: `{ val x = 1; x }`
2.  **Variables**: `val` (immutable) and `var` (mutable).
3.  **Assignment**: `x = 5` (only for `var`).
4.  **Control Flow**:
    *   `IfExpression`
    *   `MatchExpression`
    *   `LoopExpression`
    *   `LeaveExpression`
5.  **CallExpression**: `f(x)`
6.  **Struct Definition & Init**
7.  **Member Access**: `obj.field`
8.  **Intrinsic Calls**

### The Sugar (Frontend Transformation)
| Feature | De-sugars to (Core) |
| :--- | :--- |
| `while` loops | `loop` + `if` + `leave` |
| `for` loops | `loop` + index counter |
| `match?` (Non-exhaustive) | `match` with `else => null` |
| Pipe `\|>` / `-|` | Nested function calls |
| String Interpolation | String concatenation chain |
| `if` shorthand | Standard `if` block |
| `match!` (Panic match) | `match` with `else => panic` |

## 8. Deferred Features (Cut for v0)

*   **Unions / Tagged Unions**: Use structs with a "type" field for now.
*   **Rich Error Handling (`!`, `try`, `catch`)**: Use `panic` or return nullable types.
*   **Shapes & Contracts**: Only exact structure matching allowed.
*   **Opaque Types**: Treat as underlying type.
*   **Modules**: Single-file programs or simple concatenation.
*   **Memory Management**: Assume GC / leak memory.

## 9. Example: AoC Day 1 (v0 Syntax)

```matcha
item Standard = import "standard";

item main() = {
    // Library: File IO
    val input = Standard.io.readFile("input.txt");
    
    // Library: String manipulation
    val lines = input.trim().split("\n");
    
    var sum = 0;
    
    // Sugar: for loop (desugars to loop)
    for line in lines {
        // Library: String to Int
        val num = line.toInt(); 
        sum = sum + num;
    }
    
    Standard.console.log("Result: " + sum);
};

main();
```
