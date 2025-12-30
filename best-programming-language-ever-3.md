# Matcha language

## Northern star

- The story that wants to win is: match-driven programming + structural data modeling with compiler-grade guarantees, optimized for service code ergonomics.
- “Matcha makes complex data + control flow simple through pattern matching and structural data modeling, without TypeScript-style accidental footguns.”

## Story

Matcha makes shipping data-intensive applications boring to write, boring deploy, hard to get wrong, and all while making you feel smart while doing it.

### Suggestions

#### Option A (clean + credible)

Matcha makes shipping data-intensive services boring: fast to write, boring to deploy, and hard to get wrong.

#### Option B (more personality, still believable)

Matcha is for data-heavy backends where you want speed without surprises: quick builds, easy deploys, and guardrails that keep you out of trouble.

#### Option C (your “feel smart” idea, but grounded)

Matcha makes you feel smart by default: it removes the sharp edges from data-intensive services so you ship faster with fewer mistakes.

#### Other

If you want the story to actually carry a language (not just a tagline), you’ll need 2–3 proof points you can repeat everywhere, like:

“Compile fast, run fast, ship one binary.”

“Structural typing with guardrails: no accidental conformance, no mystery runtime.”

“Error handling that scales: Zig-like clarity, less ceremony.”

## Values

- Developer velocity
    - Ergonomic defaults and with explicit escape hatches
        - Structural typing with clear boundary crossing by default
            - Nominal typing via explicit escape hatch
        - Heap allocated object by default
            - Inline stack object via explicit escape hatch
        - Match-centric
            - Tagged unions (Sum Types)
    - Ergonomic deployments
        - Fast compile times
        - Single binary
        - Simple build and dependency management
- Explicitness / reducing ambiguity without verbosity
  - Explicit error handling
  - No silent "this works different now because you made this tiny implicit change"
- F
- Expressing invalid states is difficult
- Fast execution time
  - Garbage collection is fine

## Non-values

- Preventing aliasing
- System Programming
- 

## Hello world

```matcha
// Import the standard library and de-structure it to obtain the console object
item Standard = import "standard";

Standard.console.log("Hello world!");
```

## Primitives

```matcha
// integers
val integer: int = 3; // <- 64 bit integer
// Other supported types are i8, i16, i32, i64. int is just an alias for i64
val intViaSpecificLiteral = 4i16;
val decimalInt = 1_000_000;
val hexInt = 0xFF80_0000_0000_0000;
val octalInt = 0o7_5_5;
val binaryInt = 0b1_1111_1111;
val baseIntLiteralWithPrecision = 0o7_5_3i32;

// Unsigned
val unsigned: uint = 89; // <- 64 bit unsigned integer
// Other supported types are u8, u16, u32, u64. uint is just an alias for u64

// booleans
val flag: boolean = true; // internally a u1
val happy = true or (true and false); // <- type of `happy` is inferred

// floats
val floatingPoint: float = 4.3; // <- 64 bit float
// Other supported types are f8, f16, f32, f64. float is just an alias for f64
val floatLiteral = 4.3f8;

// strings
val message: string = "Hello world!"; // <- Strings are heap-allocated objects. Message is a small header to the memory on the heap
val templatedMessage: string = `${integer} is the magic number`; // <- String templating
```

## Values and variables

```matcha
val x = 4; // <- values can not be re-assigned
x = 5; // <- compile time error

var y = 4;
y = y + 1; // <- allowed
```

## Arrays

```matcha
// Like strings, arrays are heap-allocated objects. `myArray` is a small header to the memory on the heap
val myArray: float[] = [3.4, 5.6, 3.3];
val myOtherArray: Array<int> = [4, 5, 6];
val inferredTypeArray = ["hi", "ho"]; // inferred type: Array<string>

myArray[0]; // <- can be accessed with []
```

## Control Flow

## Blocks

Blocks allow grouping multiple statements and perform lexicographic scoping.

```matcha
val outsideOfBlock = 1;
{
    val insideOfBlock = outsideOfBlock + 1;
    val someOtherVariable = "hi";
}
val afterBlock = insideOfBlock; // <- would cause an error because `insideOfBlock` is not available in the scope
```

Blocks can be used as expressions. The last expression inside a block without a semicolon is what the block evaluates to.
In value producing contexts, blocks must be followed by a semicolon.

```matcha
val outsideOfBlock = 1;
val a = {
    val insideOfBlock = outsideOfBlock + 1;
    insideOfBlock / 2 // <- Notice missing semicolon
};
```

The `leave` keyword can be used to "early return" inside a block expression. It can only be used in value creating contexts and must be followed by an expression. `leave` always leaves the nearest block in case of nested blocks.

```matcha
val isHappy = true;
val isReallyHappy = {
    if isHappy leave true;
    false
};
```

Blocks can be named to leave a specific, nested block.

```matcha
val isHappy = true;
val c = outer: {
    val c1 = inner: {
        if isHappy leave :outer 42;
        43
    };
    c1
};
```

### If statement

In Matcha the if statement has no else or else if branch.

```matcha
val isHappy = (true and false) or true;
if isHappy {
    Standard.console.log("I'm happy");
}
```

Shorthand if notation for single statements:

```matcha
val isHappy = (true and false) or true;
if isHappy Standard.console.log("I'm happy");
```

### Match expression

Matcha pushes the match expression for more complex control flow branching.
Match short-circuits when encountering the first match.

```matcha
val isHappy = true;
match isHappy {
    true => Standard.console.log("I'm happy"),
    false => Standard.console.log("I'm not happy"),
}
```

The match expression must be exhaustive.

```matcha
val age = 18;
match age {
    11 => Standard.console.log("Wow you're 11"),
    16 => Standard.console.log("16, aren't we?"),
    42 => Standard.console.log("Cool age"),
    else => Standard.console.log("No comment"),
}
```

When used in value-producing contexts, match must be followed by a semicolon. All arms must return the same type.

```matcha
val isHappy = true;
val message = match isHappy { // Type of message is inferred as string
    true => "I'm happy",
    false => "I'm not happy",
};
```

The `match?` expression allows non-exhaustive matches and de-sugars into a match with an "else => null" branch.
Providing an else branch with `match?` is disallowed.

```matcha
val x = 1;
val b = match? x { // `b` has type string? (i.e. string | null)
    0 => "zero",
};
```

Match can be used without a subject. In that case every arm must provide a boolean condition to evaluate. Subjectless match must also be exhaustive.

```matcha
val x = 1;
val d = match { // subjectless match, type of d is inferred as string
    x % 2 == 0 => "even",
    x % 2 == 1 => "odd",
    else => "whoops",
};
```

`match?` can also be subjectless.

```matcha
val x = 1;
val e = match? {
    x == 0 => "zero",
} ?? "coalesced to this string";
```

## Looping

Matcha has three loop types: `loop`s, `while`-loops, and `for`-loops.

`loop`s loop forever until explicitly left with the `leave` keyword.

```matcha
var i = 0;
loop {
    i = i + 1;
    if i == 10 {
        leave;
    }
}
```

The `continue` keyword allows skipping the current loop iteration.

```matcha
var i = 0;
loop {
    i = i + 1;
    if i != 10 {
        continue;
    }
    
    leave;
}
```

`loop`s can also be used as expressions. In value-producing contexts, loop must contain at least one `leave`. Every `leave` must be followed by an expression. All paths must leave with the same type.

```matcha
var i = 0;
val result = loop { // The type of result is inferred as `int`
    i = i + 1;
    if i == 10 {
        leave i;
    }
};
```

`while`-loops are like `loops` but they continue until a specified condition is met.

```matcha
var i = 0;
while (i < 10) {
    Standard.console.log(i);
    i = i + 1;
}
```

`while`-loops can specify a continue expression.

```matcha
var i = 0;
while (i < 10) : (i = i + 1) { // `i = i + 1` is a special assignment expression
    Standard.console.log(i);
}
```

`while`-loops can also be used as an expression. In that case, each `leave` must specify a leave expression. Each leave expression must have the same return type. The return type of the while is this type or null. If no `leave` is present in the `while` loop, the return type is simply `null`.

```matcha
var i = 0;
val result = while (i < 10) : (i = i + 1) { // The type of result is inferred as `int?`
    if i == 10 {
        leave i;
    }
};

i = 0;
val result2 = while (i < 10) : (i = i + 1) { 
    if i == 10 {
        leave i;
    }
} ?? 0; // The type of result2 is inferred as `int` now
```

`for`-loops can use ranges. Ranges allow describing an integer iterator with a start, optional step, and optional end.

```matcha
for index in 0..5 { // 0..5 is a range from 0 to 4
    Standard.console.log(index);
}

for index in 10.. { // 10.. is a range from 10 to infinity
    Standard.console.log(index);
}

for index in 10..0 { // 10..0 is a range from 10 to 1
    Standard.console.log(index);
}

for index in 10..:2..100 { // 10..:2..100 is a range from 10 to 99 with a step size of 2
    Standard.console.log(index);
}

for index in 100..:2..10 { // 100..:2..10 is a range from 100 to 11 with a step size of 2
    Standard.console.log(index);
}
```

Examples of `for`-loops with arrays:

```matcha
val points = [
    .{ x = 1, y = 2 },
    .{ x = 2, y = 3 },
    .{ x = 0, y = 0 },
];
val maybePoint = for point in points { // <- Type of `maybePoint` is inferred as { x: int, y: int } | null
    if point.x == 0 and point.y == 0 {
        leave point;
    }
};

val p2 = for { x, y } in points { // <- for with destructured item
    if x == 0 and y == 0 {
        leave .{ x, y };
    }
};

val d = for (a, b) in (xs, ys) { // <- for with multiple lists, stops at shortest by definition
    if a == b {
        leave a;
    }
};

val e = for ({ a, b }, { c, d }) in (xs, ys) { // <- destructure in multi-list for
    if b == d {
        leave .{ c, d };
    }
};
```

All loop types can be labeled for leaving or continuing specific loops.

```matcha
val sortedOne = [1, 4, 6, 8, 9];
val sortedTwo = [2, 3, 5, 8, 9];
val firstMatch = outer: for (first, index) in (sortedOne, 0..) {
    inner: for second in sortedTwo {
        match? {
            first == second => leave :outer first,
            first > second => continue :inner,
            first < second => continue :outer,
        };
    }
};
```

## Functions

Functions can be defined as items, meaning they are compile-time constants. Here is how to define a function in Matcha:

```matcha
item distanceBetween(v: Vector2D, w: Vector2D): float = {
    return ((v.x - w.x)**2 + (v.y - w.y)**2)**0.5;
};
// Syntax: item <FUNCTION>(<PARAMETER_LIST>): <RETURN_TYPE> = <EXPRESSION>;
```

The function expression is just a block so you can return the last expression of the block by omitting the semicolon at the end.

```matcha
item distanceBetween(v: Vector2D, w: Vector2D): float = {
    ((v.x - w.x)**2 + (v.y - w.y)**2)**0.5
};
```

You can make this even shorter by omitting the block entirely for single expression functions.

```matcha
item distanceBetween(v: Vector2D, w: Vector2D): float = sqrt((v.x - w.x)**2 + (v.y - w.y)**2);
```

Type inference allows you to make this even shorter.

```matcha
item distanceBetween(v: Vector2D, w: Vector2D) = sqrt((v.x - w.x)**2 + (v.y - w.y)**2);
```

All of the above combined with de-structured parameters can lead to highly-scannable, low noise function definitions.

```matcha
item length({ x, y }: Vector2D) = sqrt(x**2 + y**2);
```

More examples:

```matcha
// Function definition with anonymous structure type
item length({ x, y }: { x: float; y: float }) = sqrt(x**2 + y**2);
```

```matcha
// Function definition with default parameter
item length({ x, y = 1 }: { x: float; y: float }) = sqrt(x**2 + y**2);
```

```matcha
// Function definition with shorthand de-structure anonymous structure type
item length({ x: float, y: float }) = sqrt(x**2 + y**2);
```

Functions can also be defined as runtime values using function literals:

```matcha
val isEven = function (x: int): boolean {
    return x % 2 == 0;
};
```

Single-expression functions can be wrote using the short-form notation:

```matcha
val isOdd = (x: int) => x % 2 != 0;
```

Of course this can be "abused" with the block expression:

```matcha
val signOf = (x: int) => {
    if x < 0 {
      return -1;
    }
    if x == 0 {
      return 0;
    }
    if x > 0 {
      return 1;
    }
};
```

But we all know this should have been written using a match:

```matcha
val signOf = (x: int) => match {
    x < 0 => -1,
    x > 0 => 1,
    else => 0,
};
```

In Matcha, functions are first class citizens and can be used as values.
A function item can be passed where a function value is expected; it behaves as a non-capturing callable.

```matcha
item isEven(x: int) = x % 2 == 0;
item find<Type>(array: Array<Type>, predicate: (Type) -> boolean): Type? = {
    return for item in array {
        if predicate(item) {
            leave item;
        }
    };
};
val someNumbers = [1, 2, 3, 4];
val maybeFound = find(someNumbers, isEven); // Generic type can be inferred and does not need to be specified
```

This allows for some cool stuff: partial application.

```matcha
item isEven(x: int) = x % 2 == 0;
item find<T>(predicate: (T) -> boolean) =
  (array: Array<T>) => for item in array {
      if predicate(item) leave item;
  };

val findIsEven = find(isEven);
val someNumbers = [1, 2, 3, 4];
val maybeFound = findIsEven(someNumbers);
```

## Pipe Operator

The `-|` pipe operator allows you to pipe a value as the first argument of a function

```matcha
item someFunction(x: Vector) = /* ... */;
val vector: Vector = .{ /* ... */ };

vector -| someFunction;
```

This allows to write chains of pipes in a nice, bullet point style list:

```matcha
val listOfStructures
    -| toListOfOtherStructures
    -| filter
    -| mapToInts
    -| sum;
```

x -| f(args...) desugars to f(x, args...)
x -| f desugars to f(x)

## Structures

### 1) Structures

**Concrete, constructible, exact record types.**

* Named `structure` is **closed**: it has exactly its declared fields.
* Named structures do **not** implicitly convert to other named structures (no width subtyping).
* Literals can be used to construct them if fields match exactly.

```matcha
item Vec2D = structure { x: float; y: float; };
val v = Vec2D { x=1, y=2 };
```

### 2) Shapes

**Structural “record constraints” for parameters/generics.** Not constructible.

* `{ x: float; y: float }` = exact shape (closed)
* `{ x: float; y: float; .. }` = open shape (“at least these fields”)
* Used to accept anonymous records or any value with matching fields.

```matcha
item Vec2Like = shape { x: float; y: float; };
item length(v: Vec2Like) = ...
```

### 3) Contracts

**Behavior requirements (methods), not data layout.**

* Used when you need polymorphism, dispatch, or “must provide these functions”.
* Should not be satisfied “by accident” unless you explicitly state that.
* Structures can explicitly satisfy shapes.

```matcha
item HasLength = contract { length(self): float; };
item magnitude(v: HasLength) = v.length();
```

### 4) Opaque primitives

**Newtype over a primitive. Same runtime rep, distinct type.**

* No implicit conversion to/from the underlying primitive.
* Used for IDs, tokens, units, etc.

```matcha
item UserId = opaque string;
val userId = UserId("123abc");

item OrgId = opaque string {
    item fromUserId(userId: UserId) = OrgId(userId); // UserId is allowed where a string is expected
};
```

### 5) Opaque structures

**Concrete structures with identity + invariants.**

* Allow private fields
* Mandatory constructor
* No structural coercion from literals or other records unless via the constructor.
* Used when correctness beats convenience.

```matcha
item User = opaque structure {
  id: UserId;
  // private/internal fields allowed
};
```

### One key consistency rule

* **Exact by default.**
* **Open-ness must be spelled** (`..` in shapes).
* **Dropping fields must be explicit** (spread construction), never silent.

That’s the whole system: **structures = data**, **shapes = field-based acceptance**, **contracts = behavior**, **opaque = identity/invariants**.


### Basics

Matcha does not have classes or inheritance, only structures. Structures are exact, closed sets of key value pairs. They need to be defined as item. Items are compile time entities like function, enums, errors, contracts etc. They must be placed at the top level of a file. Matcha has a semi-structural and semi-nominal. More on that later.

```matcha
item User = structure {
    name: string;
    age: int;
    isCool: boolean = false; // Member variable with a default argument
};

// Here is an example of instantiating an object that satisfies the `User` structure
// Every non-default field has to be specified.
val tom = User {
    name = "Tom",
    age = 32,
    // isCool can be omitted because it is false by default
};

// Because the type of `greg` is specified, the shorthand "dot" notation can be used here for object literals
var greg: User = .{
    name = "Greg",
    age = 23,
    isCool = true, // <- default value is overriden during instantiation
};

val name = "Mario";
val age = 26;
val mario: User = .{ name, age }; // shorthand notation to prevent having to write name = name etc.
val alex = User { name, age }; // Syntactic sugar for defining an object that satisfies the `User` structure.
// The type of `alex` is inferred as User.
```

Object can also be created with "unstructured" object literals.

```matcha
// The type of `unstructuredObject` is inferred as exactly `{ someKey: string }`
val unstructuredObject = .{
    someKey = "someValue",
};
// objects can be de-structured and the type of someKey can be inferred from unstructuredObject's type
val { someKey } = unstructuredObject;
```


### Mutability

// TODO:

### Opaque types

```matcha
// "Nominal wrappers" (opaque) for meaning-carrying primitives
item UserId = opaque string; // nominal identity, runtime is just string
item OrgId = opaque string;
val userId = UserId("abc123");
val orgId = OrgId("123abc");

item loadUser = function (id: UserId) {...};

loadUser(orgId); // rejected
// it kills the most common accidental conformance: “everything is a string/int”.
```

1. Zero-overhead, guaranteed: compiler promises it’s represented exactly like string (no wrapper object, no field access). A nominal struct can be optimized to that, but “opaque” makes it a language guarantee.
2. Better ergonomics for primitives: you don’t want .value everywhere for IDs. You want it to behave like a string only when you ask.
3. Control of API surface: you can expose only safe constructors:
```matcha
item Email = opaque string;
item parseEmail = function (s: string) -> Result<Email, InvalidEmail> { ... };
// no implicit Email("lol") unless you allow it
```
With nominal struct, people can often construct it “raw” unless you add extra rules.
So: nominal structure is a general-purpose “object with identity”.
opaque is a laser-focused “distinct primitive with controlled escape hatches”.

### Conformance

```matcha
item Organization = structure {
    name: string;
};
item User = structure {
    name: string;
};
item UserUpdateDto = structure {
    name: string;
    wasValidated: boolean;
};

item greetUser(user: User) = {
    ...
};
item greetSomethingWithExactlyName(something: { name: string }) = {
    ...
};
item greetSomethingWithExactlyNameAndMore(something: { name: string, other: string }) = {
    ...
};
item greetAnythingWithName(user: { name: string, .. }) { // the `..` express a `shape` that allows anything with the given fields
    ...
};

val user: User = .{
    name: "Tom",
};
val org: Organization = .{
    name: "Chili's",
};
val userUpdateDto: UserUpdateDto = .{
    name: "Jerry",
    wasValidated: true,
};
val randomStructureWithName = .{
    name: "Random",
};
val randomStructureWithNameAndMore = .{
    name: "Random",
    other: "property",
};

// Named structures cannot accidentally conform to other named structures, unless explicitly converted to one another.
Explained using examples
greetUser(user); // ✅ accepted because user has the User type
greetUser(userUpdateDto); // ❌  rejected because `userUpdateDto` is not of type `User`
greetUser(User { ...userUpdateDto }); // ✅ accepted because `userUpdateDto` has been explicitly used to construct a `User`. `userUpdateDto`'s excess fields are dropped here
greetUser(org); // ❌ rejected because org is not of type `User`
val userFromOrg = User { // Explicit conversion boundary, construct a user from an org by spreading its fields
    ...org, // org must have at least the fields of User
    // Excess fields are "dropped" here, because a user doesn't have them
    // This constructs a new user by copying the org fields into the new User object
};
greetUser(userFromOrg); // ✅ accepted
greetUser(User { ...org }); // ✅ accepted because `org` has been explicitly used to construct a `User`. `org`'s excess fields are dropped here
greetUser(randomStructure); // ❌ rejected because the anonymous type of `randomStructure` is not user
greetUser(User { ...randomStructure }); // ✅ accepted because `randomStructure` has been explicitly used to construct a `User`. `randomStructure`'s excess fields are dropped here

greetSomethingWithExactlyName(user); // ✅ accepted because the `User` type exactly matches the anonymous type of greetSomethingWithExactlyName
greetSomethingWithExactlyName(userUpdateDto); // ❌ rejected because `userUpdateDto` is not of type `{ name: string }`
greetSomethingWithExactlyName(.{ ...userUpdateDto }); // ✅ accepted because `userUpdateDto` has been explicitly used to construct a anonymous structure. `userUpdateDto`'s excess fields are dropped here
greetSomethingWithExactlyName(org); // ✅ accepted because the `Organization` type exactly matches the anonymous type of greetSomethingWithExactlyName
greetSomethingWithExactlyName(randomStructureWithName); // ✅ accepted because `randomStructureWithName`'s type exactly matches the anonymous type of greetSomethingWithExactlyName
greetSomethingWithExactlyName(randomStructureWithNameAndMore); // ❌ rejected because `randomStructureWithNameAndMore`'s type does not exactly match the anonymous type of greetSomethingWithExactlyName
greetSomethingWithExactlyName(.{ ...randomStructureWithNameAndMore }); // ✅ accepted because `randomStructureWithNameAndMore` has been explicitly used to construct a anonymous structure. `randomStructureWithNameAndMore`'s excess fields are dropped here

greetAnythingWithName(user); // ✅ accepted because greetAnythingWithName expects an open shape with at least a `name` field
greetAnythingWithName(userUpdateDto); // ✅ accepted because greetAnythingWithName expects an open shape with at least a `name` field
greetAnythingWithName(org); // ✅ accepted because greetAnythingWithName expects an open shape with at least a `name` field
greetAnythingWithName(randomStructureWithName); // ✅ accepted because greetAnythingWithName expects an open shape with at least a `name` field
greetAnythingWithName(randomStructureWithNameAndMore); // ✅ accepted because greetAnythingWithName expects an open shape with at least a `name` field
```

### Contracts

```matcha
// Contracts are similar to interfaces in other programming languages.
// They specify only the shape of an object but never their value.
// Inside a contract, self means the contract type, not the implementer. It desugars into the contract name
item Point = contract {
    x: int;
    y: int;
    distanceTo: (this: self, other: self) -> float;
};

// Instantiating a value that satisfies a contract.
val somePoint: Point = .{
    x = 3,
    y = 7,
    // Satisfying the contract requires having to provide implementation details for the distanceTo function.
    // In matcha, functions are just values so specifying an implementation for a function is nothing more
    // than assigning a function literal to a field of the object.
    distanceTo = function (this: self, other: self): float {
        return ((other.x - this.x)**2 + (other.y - this.y)**2)**0.5;
    };
};

// Some other value
val someOtherPoint: Point = .{
    x = -3,
    y = 8,
    // This "instance of a point" provides a different definition for how it computes distances
    distanceTo = function (this: self, other: self): float {
        return ((other.x - this.x)**2 + (other.y - this.y)**2);
    };
};

// Conceptually, every object has a pointer to it's "own" distanceTo function.
// In reality:
// 1) Static dispatch (direct call)
// If the compiler knows the concrete structure type at compile time and the function is type-level:
// val c: Vector1 = .{ x = 1, y = 3 };
// c.distance(...)
// This can compile to:
// Vector1.distance(c, ...)
// That’s a direct call. No vtable needed.
// 2) Calling a function stored in the object (indirect call, but not “vtable dispatch”)
// If someOtherDistance is a field that holds a function value:
// c.someOtherDistance(...)
// val computeDistanceBetween = function (a: Point, b: Point): float {
//     return a.distanceTo(b);
// };
// This compiles to:
// load the function pointer from the object
// call it
// 3) Contract-typed value (interface pair: data pointer + vtable pointer)
// If you have:
// item VectorContract = contract {
//   val yetAnotherDistance: (this: self, other: self) -> float;
// };
// item Z = structure satisfies VectorContract {
//   item yetAnotherDistance = function(...) { ... } // type-level method
// };
// val zc: VectorContract = Z { ... };
// Then zc at runtime becomes something like:
// data_ptr → points to the Z instance
// vtable_ptr → points to “Z as VectorContract” method table
// Calling:
// zc.yetAnotherDistance(...)
// becomes:
// zc.vtable.yetAnotherDistance(zc.data, ...)
// that’s vtable dispatch.
// TODO: Don't know how to handle re-assignment of function value yet.

// These distances won't be the same
val distanceFromSomePointToSomeOtherPoint = computeDistanceBetween(somePoint, someOtherPoint);
val distanceFromSomeOtherPointToSomePoint = computeDistanceBetween(someOtherPoint, somePoint);
// This is an example of runtime polymorphism in matcha: depending on the actual point, the right
// distanceTo function is used.

// Structures can satisfy a contract.
item EuclideanVector = structure satisfies Point {
    // `x` and `y` are already specified on the `Point` contract.
    // The contract's `distanceTo` function receives an immutable default value for a `EuclideanVector`
    distanceTo = function (this: self, other: self): float {
        return ((other.x - this.x)**2 + (other.y - this.y)**2)**0.5;
    };
};

val v1 = EuclideanVector {
    x = 4,
    y = 3,
};
val v2 = EuclideanVector {
    x = 2,
    y = 8,
};
val areSymmetric = computeDistanceBetween(v1, v2) == computeDistanceBetween(v2, v1);
// `areSymmetric` is true
```

### Nominality

```matcha
item Vector = contract {
    x: float;
    y: float;
    distanceTo: (this: self, other: self) -> float;
};

item StrangeVector = structure satisfies Vector {
    distanceTo = function (this: self, other: self): float {
        return (other.x - this.x)**2 + (other.y - this.y)**2;
    };
};

item EuclideanVector = nominal structure satisfies Vector {
    distanceTo = function (this: self, other: self): float {
        return ((other.x - this.x)**2 + (other.y - this.y)**2)**2;
    };
};

val computeEuclideanDistanceBetween = function (v1: EuclideanVector, v2: Vector): float {
    return v1.distanceTo(v2);
};
val computeStrangeDistanceBetween = function (v1: StrangeVector, v2: Vector): float {
    return v1.distanceTo(v2);
};

val strangeVector = StrangeVector {
    x = 4,
    y = 9,
};
val euclideanVector = EuclideanVector {
    x = 3,
    y = -2,
};

computeStrangeDistanceBetween(strangeVector, euclideanVector); // ✅ this is okay because all structures are satisfied
computeStrangeDistanceBetween(euclideanVector, strangeVector); // ✅ this is okay because all structures are satisfied
computeEuclideanDistanceBetween(euclideanVector, strangeVector); // ✅ this is okay because all nominal types and structures are satisfied
computeEuclideanDistanceBetween(strangeVector, euclideanVector); // ❌ is not okay because `strangeVector` does not satisfy the nominal type


item User = nominal structure {
    // Fields are public by default
    coolAttribute: string;

    // Nominal structures can have private fields
    private secret: string;

    // Both nominal and non-nominal structures can have a constructor but it must be used if defined
    constructor (
        // Constructor property promotion
        public firstName: string,
    ) {
        // The constructor must initialize all uninitialized fields
        secret = firstName;
        coolAttribute = firstName;
    };
};

// Initializing structures with a constructor must use () instead of {} and initialize all constructor fields.
// Type of user is inferred
val user = User(firstName = "Mario");
// Because the type of `otherUser` is clear, the shorthand .() notation can be used.
val otherUser: User = .(firstName = "Norman");
```

## Modules and other

```matcha
// File: immutable-point.mt
// exporting an item or value makes them accessible in other files via an import
export item ImmutablePoint = contract {
    x: float;
    y: float;

    length: (this: self) -> float;
    lengthSquared: (this: self) -> float;
    lengthCubed: (this: self) -> float;
    addedTo: (this: self, other: self) -> self;
};


// File math.mt
// exporting a single value
export val pi = 3.1415;


// main.matcha
// importing something from a different file creates a module item
item Math = import "math.mt";
// modules can be deconstructed for easy access
item { ImmutablePoint } = import "immutable-point.mt";

// Define a structure that satisfies one of the contracts we imported.
// A structure can satisfy one or more contracts.
item Vector = structure satisfies ImmutablePoint {
    // Some field for educational purposes
    cachedLength: float;
    
    // A structure can have a constructor that handles initialization
    constructor (
        // Constructor property promotion to satisfy interface
        public x: float,
        public y: float,
    ) {
        cachedLength = (x**2 + y**2)**0.5; // <- constructor simply does "raw" initialization
        // No access to half-initialized "this" in the constructor
    };

    // satisfy the contract
    var length = function(this: self): float {
        return (this.x**2 + this.y**2)**0.5;
    }

    // Shorthand notation, types can be omitted since they can be inferred from the contract
    var lengthSquared = (this) => {
        return this.x**2 + this.y**2;
    };

    // Since parameter types can be inferred, parameter destructuring makes this nice and short
    var lengthCubed = ({x, y}) => (x**2 + y**2)**(3/2);

    // satisfy the contract
    val addedTo = function({x, y}, other) {
        // A "structured" instantiation of a Vector with the () notation instead of the {} must be used because a constructor has been defined
        return Vector(
            x + other.x,
            y + other.y,
        );
    };

    // Other function not part of the contract
    val asNormalized = function({ x, y }: self): self {
        // Accessing a callable desugars into a function where receiver is passed as the first argument, hence we can omit the receiver in the surface language to achieve a nice, method-like syntax without having classes
        val length = this.length();
        // Since the return type can be inferred, we can use the shorthand dot notation
        return .(
            x / length,
            // Named parameter
            y = y / length,
        );
    };

    val projectedUp = function ({ x }: self) {
        return .(
            x,
            0
        );
    };
};

// Instantiating a structure with a constructor requires you to use it.
val myVector = Vector(x = 3, y = 7);
```

## Wild west of ideas

### Generics for compile-time polymorphism

- Don't want to spec this out because it seems complicated and I'm pretty sure extending the existing syntax for generics should be straight forward

### Async an IO

- Don't want to spec this out because it seems complicated and I'm pretty sure extending the existing syntax for IO should be straight forward

### Unrecoverable errors

```matcha
item YouMessedUpBad = panic {
    YourProgramCrashedHard: inline structure { message: string };
    ItCrashedReallyHardMyBoy: inline structure { message: string };
};

val doSomethingDangerous = function () {
    // ... control flow
    panic YouMessedUpBad.YourProgramCrashedHard(.{ message: "Big oof" }); // <- panics cannot be recovered with `try` and `catch`
};

supervise { // <- supervise blocks are only allowed at main.mt or "dedicated entry functions"
    return doSomethingDangerous();   // normal returns and recoverable errors live here
} on panic (YouMessedUpBad p) {
    match (p) {
        .YourProgramCrashedHard => logCrashA(p),
        .ItCrashedReallyHardMyBoy => logCrashB(p),
    };
    return Response(500);
}
```

### Type functions / comptime functions

```matcha
item AuditLogType = enum { NewsletterPreferenceUpdated, ShopDeleted };

item MetaFor = comptime (t: AuditLogType) => match (t) {
  .NewsletterPreferenceUpdated => structure { newsletterOptIn: bool },
  .ShopDeleted => structure { shopUuid: string, shopDomain: string },
};

item AuditLog<T: AuditLogType> = structure {
  type: T = T;
  common: Common;
  metadata: MetaFor(type); // allowed because type == T is compile-time
};

// Generic type of log is inferred from the `type` property, so it does not need to be specified
val log: AuditLog = .{
    type = .NewsletterPreferenceUpdated
    common = .{ remoteIp = "::ffff:127.0.0.1" },
    metadata = .{ newsletterOptIn = false }, // `type` property decides the type of `metadata`
};

```

## TODO:

- Enums
- Tagged Unions
- Error Values
- Panic Values
- Shapes vs Contracts
- all non-void values must be used (or explicitly discarded with _ = ...)
- Godot and scala type match expressions on steroids

### match! (non-exhaustive panic match)

The `match!` expression allows non-exhaustive matches but de-sugars into a match with an "else => panic" branch.
Providing an else branch with `match!` is disallowed.

```matcha
val x = 1;
val c = match! x { // `c` has the type string but this can fail at runtime if x is not 0
    0 => "zero",
};
```

`match!` can also be subjectless:

```matcha
val x = 1;
val f = match! { // subjectless match that de-sugars to "else => panic" branch
    x % 2 == 0 => "even",
    x % 2 == 1 => "odd",
};
// the type of f is inferred as string but the match _can_ fail at runtime, even though it logically shouldn't
```

### Semi-destructuring with @ notation

The `@` notation allows you to destructure only parts of a parameter while keeping a reference to the whole value.

```matcha
// Function definition with semi-de-structured parameter
item length(v@{ y }: Vector2D) = sqrt(v.x**2 + y**2);
```

```matcha
// Function definition with shorthand semi-de-structure anonymous structure type and default parameter
item length(v@{ x: float, y: float = 1 }) = sqrt(v.x**2 + y**2);
```

```matcha
// For loops with semi-destructured items
val p3 = for point@{ x, y } in points {
    if point.x == 0 and point.y == 0 {
        leave point;
    }
};
```

```matcha
// Multi-list for with semi-destructuring
val e = for ({ a, b }, y@{ c, d }) in (xs, ys) {
    if b == d {
        leave y;
    }
};
```

### Array slice syntax

Yes. The clean way is: make slices accept a range expression inside []. Then your existing range syntax is the slice syntax.

Basic slices
a[i..j]   // like Python a[i:j]
a[i..]    // a[i:]
a[..j]    // a[:j]
a[..]     // a[:]

Stepped slices (using your preferred :k)
a[i..:k..j]   // a[i:j:k]
a[i..:k..]    // a[i::k]
a[..:k..j]    // a[:j:k]
a[..:k..]     // a[::k]

About negative / reverse

Python doesn’t “infer direction”. It uses the sign of step. If you want Python-like reversing, you’ll want an explicit signed step form too, for sanity:

a[i..-1..j]   // explicit negative step (reverse)
a[..-1..]     // reverse whole array


Rule of thumb:

..:k.. = magnitude-only stride (direction inferred if you insist, or just treat it as positive)

..k.. = explicit signed stride

That gives you nice syntax and avoids mysterious empty slices when someone goes 10..:2..0.


### Structure Union

```matcha
item LetNode = structure {
    identifier: string;
    expression: string;
};

item SubtractionNode = structure {
    lhs: string;
    rhs: string;
};

// A node is now either a LetNode or a SubtractionNode
item Node = LetNode | SubtractionNode;
// Union structures cannot be instantiated, you cannot type a variable as an Union structure
val node: Node = .{}; // <- this is not allowed


item stringifyNode = (node: Node) => match (node) {
    LetNode => `${node.identifier} = ${node.expression};`,
    SubtractionNode(subtractionNode) => `${subtractionNode.lhs} - ${subtractionNode.rhs}`, // optional capture
};
```

### Structure Intersections

```matcha
item IdRow = structure {
    id: string;
};
item BaseRow = structure {
    createdAt: string;
    updatedAt: string;
};
item VersionRow = structure {

};

item UserRow = BaseRow & structure {
    
};
```


### Memory allocation

```matcha
// For ergonomics, per default, structures are always handles to heap-allocated and GC-managed values
item User = structure {
    age: int;
    name: string;
};
val user = User { name = "Mario", age = 26 }; // <- `user` is only a handle that points to heap allocated data
val userB = user; // <- userB and user now point to the same piece of memory

val greet = function (user: User) { // <- per default, `user` is always "passed by reference", i.e. the handle to the heap-allocated object is copied but the copy points to the same object in memory
    print(`Hi ${user.name}!`);
};

// For tighter control, the `inline` modifier can be used on a structure
// Inline structures are stored inline wherever they appear (stack, inside other structs, inline in arrays)
// Passing them copies or moves the bytes (compiler can optimize)
// No hidden heap handles.
// Nested inline structure fields of inline structures are copied deeply with the parent structure.
item UserUpdateDto = inline structure {
    user: User; // <- inline structures can contain handles to heap objects, the handle is also copied
    // “Heap-handle fields inside inline structs are copied as handles (shallow), not deep-cloned.”
    newAge: int;
};

val userUpdateDto = UserUpdateDto { user, newAge = 27};
val apply = function (dto: UserUpdateDto) { //
    // ...
};
apply(userUpdateDto); // <- this invocation creates a copy of `userUpdateDto` and passes it to `apply`

val userUpdateDtoReference = &userUpdateDto; // Explicit heap allocation, type of `userUpdateDtoReference` is now Handle<UserUpdateDto>

userUpdateDtoReference.newAge = 42; // desugars to (*userUpdateDtoReference).newAge = 42 and mutates heap copy

val otherApply = function (dtoReference: Handle<UserUpdateDto>) {
    // ...
};
otherApply(userUpdateDtoReference); // <- passes only handle to `userUpdateDto`
otherApply(&userUpdateDto); // <- explicitly create handle and pass it to function
// structure types are already handles. No Handle<structure> allowed.
// Handle<T> only exists for inline types (boxing).u
```
