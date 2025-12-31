# Learn Matcha in Y Minutes

Matcha is a compiled backend language designed to make shipping data-intensive services boring: fast to write, boring to deploy, and hard to get wrong. It combines TypeScript-like data shaping with Zig/Rust-like exhaustiveness and error clarity.

Key features:
- **Match-driven programming**: Control flow is centered around pattern matching.
- **Structural data modeling**: A unique system distinguishing between exact structures (data layout) and open shapes (constraints).
- **Rich Error Unions**: Errors are values, but with special syntax for ergonomic propagation and composition.
- **Expression-based**: Blocks, loops, and conditionals return values.

```matcha
// Single-line comments start with //

/*
  Multi-line comments look like this.
*/

//////////////////////////////////////////////////
// 1. Primitives and Variables
//////////////////////////////////////////////////

// Import the standard library
item Standard = import "standard";

// Variables are declared with `val` (immutable) or `var` (mutable).
val x = 42;
// x = 43; // Error: cannot re-assign val

var y = 10;
y = 11; // OK

// Integers (i8, i16, i32, i64/int, u8... u64/uint)
val intVal: int = 100;
val hexVal = 0xFF;
val binaryVal = 0b1010;

// Floats (f8, f16, f32, f64/float)
val pi: float = 3.14159;

// Booleans
val isHappy: boolean = true;

// Strings (Heap allocated)
val name = "Matcha";
val greeting = `Hello, ${name}`; // String templating

// Arrays (Heap allocated)
val numbers: int[] = [1, 2, 3];
val floats = [1.1, 2.2]; // Inferred as float[]

// Value Usage Rule:
// All non-unit values must be used or explicitly discarded.
// This prevents "silent failures" where a result is ignored.
item add(a: int, b: int) = a + b;

// add(1, 2); // Error: unused value
val sum = add(1, 2); // OK
_ = add(1, 2);       // OK, explicitly discarded


//////////////////////////////////////////////////
// 2. Control Flow
//////////////////////////////////////////////////

// Blocks are expressions.
// The last expression without a semicolon is the return value.
val result = {
    val a = 10;
    val b = 20;
    a + b // Returns 30
};

// `leave` can be used to exit a block early with a value.
val early = {
    if true leave 100;
    200
};

// If statements
// Note: No `else if`. Use `match` for complex branching.
if isHappy {
    Standard.console.log("Yay!");
}

// Match expressions (The heart of Matcha)
// Must be exhaustive.
val status = match x {
    0 => "Zero",
    1 => "One",
    else => "Many",
};

// `match?` allows non-exhaustive matching (returns nullable type).
val maybeString: string? = match? x {
    42 => "The answer",
};

// Subjectless match (like switch(true))
val description = match {
    x < 0 => "Negative",
    x > 0 => "Positive",
    else => "Zero",
};

// Loops
// Loops are expressions and can return values via `leave`.

// 1. Infinite loop
var i = 0;
val loopResult = loop {
    i = i + 1;
    if i == 10 leave i; // Returns 'i' from the loop expression
};

// 2. While loop
// Can specify a 'continue expression' after the condition (like C-style for loop step)
while (i > 0) : (i = i - 1) {
    Standard.console.log(i);
}

// While as an expression (returns T?)
// Returns the value of 'leave' or null if the loop finishes naturally.
val found = while (i < 10) : (i = i + 1) {
    if i == 5 leave "Found 5";
}; // found is string?

// 3. For loop (Ranges and Iterators)
for idx in 0..5 { // 0 to 4
    Standard.console.log(idx);
}

// Multi-list iteration (zips lists, stops at shortest)
val xs = [1, 2, 3];
val ys = [10, 20];
for (x, y) in (xs, ys) {
    Standard.console.log(x + y);
}

// For as an expression (returns T?)
// Useful for searching.
val points = [.{ x=1, y=2 }, .{ x=0, y=0 }];
val origin = for { x, y } in points {
    if x == 0 and y == 0 leave .{ x, y };
}; // origin is { x: int; y: int }?


//////////////////////////////////////////////////
// 3. Functions
//////////////////////////////////////////////////

// `item` defines compile-time constants (top-level functions).
item multiply(a: int, b: int): int = {
    return a * b;
};

// Short syntax for single expressions (implicit return)
item divide(a: int, b: int) = a / b;

// Function literals (runtime values)
val subtract = (a: int, b: int) => a - b;

// Pipe Operator (-|)
// Pipes the value as the first argument of the function.
// x -| f  desugars to f(x)
val raw = 10;
val computed = raw
    -| add(5)      // add(raw, 5)
    -| divide(3);  // divide(result, 3)


//////////////////////////////////////////////////
// 4. Data Modeling (The "Killer Feature")
//////////////////////////////////////////////////

// Matcha's data modeling system is designed to prevent "accidental conformance"
// while keeping the ergonomics of structural typing where it matters.
// It distinguishes between:
// 1. Structures (Data Layout)
// 2. Shapes (Constraints)
// 3. Contracts (Behavior)
// 4. Opaque Types (Identity)

// --- A. Structures (Exact & Nominal-ish) ---
// Structures are closed sets of fields. They are "exact" types.
// They do NOT implicitly conform to one another, even if fields match.
item User = structure {
    name: string;
    age: int;

    // Non-opaque structures can also have methods!
    // Must explicitly take 'this' as the first parameter.
    item isAdult(this: self): boolean = this.age >= 18;
};

item Admin = structure { name: string; age: int; role: string; };

val user: User = .{ name = "Alice", age = 30 };
val adult = user.isAdult();
val admin: Admin = .{ name = "Bob", age = 40, role = "Root" };

item processUser(u: User) = ...;

// processUser(admin); // Error! Admin is not User.
// This prevents passing an Admin where a User is expected just because they share fields.

// --- B. Spread Projection (Safe Conversion) ---
// To convert data between structures, you use Spread Projection.
// The compiler "projects" the spread value onto the target type,
// automatically dropping extra fields and checking for missing ones.

val userFromAdmin = User { ..admin }; // OK! 'role' is safely dropped.
// val adminFromUser = Admin { ..user }; // Error! Missing 'role'.

// --- C. Shapes (Structural Constraints) ---
// Shapes describe requirements for data. They are useful for function arguments
// that accept any object with specific fields.
// Unlike structures, shapes are "open" (structural typing).
// An object satisfies a shape if it has *at least* the required fields.
//
// NOTE: Shapes cannot be used as concrete types (e.g. `val x: Shape = ...`).
// They are only used as constraints for function parameters or generics.

item HasName = shape { name: string; };

item printName(obj: HasName) = Standard.console.log(obj.name);

printName(user);  // OK: User has 'name'
printName(admin); // OK: Admin has 'name' (and other fields)
printName(.{ name = "Anonymous", id = 123 }); // OK: Anonymous object works too

// --- D. Contracts (Behavioral Interfaces) ---
// Contracts define behavior (methods), not data layout.
// Structures must EXPLICITLY satisfy contracts.

item Printable = contract {
    toString(this: self): string;
};

// A structure satisfying a contract
item Person = structure satisfies Printable {
    name: string;
    
    // Implementation of the contract method
    item toString({ name }: Person): string = `Person: ${name}`;
};

item printIt(p: Printable) = Standard.console.log(p.toString());

printIt(Person { name = "Dave" });

// Contracts can also be satisfied by anonymous structures (vtables created automatically)
val anonPrintable: Printable = .{
    name = "Ghost",
    toString = ({ name }: self) => `Ghost: ${name}`,
};


//////////////////////////////////////////////////
// 5. Opaque Types (Safety & Invariants)
//////////////////////////////////////////////////

// --- A. Opaque Primitives ---
// Zero-overhead wrappers. At runtime, this is just a string.
// At compile time, it is a distinct type that cannot be mixed with string.
// This solves the "Primitive Obsession" problem.
item UserId = opaque string;
item Email = opaque string;

val uid = UserId("u_123");
// val s: string = uid; // Error: UserId is not string
// val e: Email = uid;  // Error: UserId is not Email

// --- B. Opaque Structures ---
// Used for enforcing invariants. They can have private fields and constructors.
// This is Matcha's answer to Classes.
item BankAccount = opaque structure {
    public owner: string;
    private balance: int; // Cannot be accessed outside this module

    // Constructor is mandatory if defined.
    constructor(ownerArg: string, initialDeposit: int) {
        // Fields are initialized directly by name (no 'this')
        owner = ownerArg;
        balance = if initialDeposit < 0 { 0 } else { initialDeposit };
    };

    // Methods must explicitly take 'this' as the first parameter
    item deposit(this: self, amount: int) = {
        this.balance = this.balance + amount;
    };
};

val account = BankAccount("Alice", 100);
// account.balance = 1000; // Error: private field


//////////////////////////////////////////////////
// 6. Unions and Pattern Matching
//////////////////////////////////////////////////

// Tagged Unions (Sum Types)
item Shape = union {
    Circle: float,             // Payload: radius
    Rectangle: { w: float; h: float }, // Payload: struct
    Point,                     // No payload
};

val c = Shape.Circle(10.0);

// Pattern matching on unions
item area(s: Shape): float = match s {
    .Circle(radius) => pi * radius * radius,
    .Rectangle({ w, h }) => w * h,
    .Point => 0.0,
};


//////////////////////////////////////////////////
// 7. Error Handling & Composition
//////////////////////////////////////////////////

// Errors are tagged unions.
item FileError = error { NotFound, AccessDenied };
item ParseError = error { InvalidFormat, Overflow };

// --- A. Basic Propagation ---
// Functions return `ErrorType!SuccessType`
item readFile(path: string): FileError!string = {
    if path == "" return .NotFound;
    return "123";
};

// --- B. Error Composition ---
// When a function can fail in multiple ways (e.g. reading AND parsing),
// you define a composite error type.

item ConfigError = error {
    File: FileError,   // Wraps file errors
    Parse: ParseError, // Wraps parse errors
};

item loadConfig(path: string): ConfigError!int = {
    // `try` ... `catch` allows mapping errors to the composite type.
    val content = try readFile(path) catch (e) {
        return .File(e); // Wrap FileError into ConfigError.File
    };

    // If we had a parse function:
    // val num = try parse(content) catch (e) return .Parse(e);
    
    return 0;
};

// --- C. Try/Catch Expressions ---
// `try` is an expression. The catch block must return the same type as the success path,
// OR return/leave from the parent function.

val result = try readFile("config.txt") catch (err) {
    match err {
        .NotFound => "default_value", // Recover with default
        .AccessDenied => {
            Standard.console.log("CRITICAL FAILURE");
            leave "empty"; // Early exit from block
        }
    }
};
```
