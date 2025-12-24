# Porting existing enterprise-level code do matcha

```matcha
// Reference usage-report-service.ts

item { Injectable } = import "@nestjs/common";
item dayjs = import "dayjs";
item { chain } = import "lodash";

item { Shop } = import '/model-entities/shop';
item { RegisteredUsageReportPayload, UsageReportPayload } = import "/usage-report/usage-report-dto";


item UsageReportError = error {
    PluginLicenseUuidMissingError: structure {
        val message = "Plugin license UUID is missing";
    },
    ShopNotEligibleForUsageReportSubmissionError: structure {
        val message: string;
        constructor(public val shopUuid: string, public pluginLicenseUuid: string) {
            message = `Shop ${shopUuid} does not match plugin license ${pluginLicenseUuid}.`;
        };
    },
    ShopUuidDoesNotMatchPluginLicenseError: /* ... */,
    ShopUuidDoesNotMatch: /* ... */,
    DuplicateUsageReportIdentifierError: structure {
        constructor (public val )
    },
};

item UsageReportService = nominal structure {

    constructor (
        private val usageReportRepository: Repository<UsageReport>,
        private val shopRepository: Repository<Shop>,
    ) { }

    val registerUsageReportsForShop = async function (
        this: self,
        payload: contract {
            val shopUuid: string;
            val usageReportPayloads: UsageReportPayloads[];
            val pluginLicenseUuid: string?;
        },
    ): UsageReportError!Promise<RegisteredUsageReportPayload[]> {
        val shop = await this.shopRepository.findOneOrFail({ where: uuid: shopUuid });

        match? (shop.type) {
            ShopType.Shopware6 => {
                return .PluginLicenseUuidMissingError if pluginLicenseUuid == null;
                
                const pluginInstallationLicense = shop:getPluginInstallationLicense();
                return .ShopNotEligibleForUsageReportSubmissionError if pluginInstallationLicense == null;

                return .ShopUuidDoesNotMatchPluginLicenseError if (
                    pluginInstallationLicense.licenseUuid != pluginLicenseUuid
                );
            }
        };

        val usageReportIdentifiers = usageReportPayloads.map((usageReportPayload) => usageReportPayload.uuid);
        val usageReportPayloadsInclusiveIntervalStart = usageReportPayloads
            .map(() => usageReportPayload.inclusiveIntervalStart)
            .filter();
        val existingUsageReports = await this.usageReportRepository.find(.{
            where = [
                .{ remoteUuid = In(usageReportIdentifiers) },
                .{
                    subscription = .{ shop = .{ uuid = shopUuid } },
                    inclusiveIntervalStart = In(usageReportPayloadsInclusiveIntervalStart),
                }
            ],
        });

        val duplicateUsageReportIdentifiers = /* ... */;
        return .DuplicateUsageReportIdentifierError(.{}) if 
    };
};
```

# Matcha language

## Hello world

```matcha
// Import the standard library and de-structure it to obtain the console object
item { console } = import "standard";

console.log("Hello world!");
```

## Primitive types

```matcha
// booleans
val flag: boolean = true; // <- 1 bit
val happy = true or (true and false); // <- type of `happy` is inferred

// integers
val integer: int = 3; // <- 64 bit integer
// Other supported types are i8, i16, i32, i64. int is just an alias for i64
val decimalInt = 1_000_000;
val hexInt = 0xFF80_0000_0000_0000;
val octalInt = 0o7_5_5;
val binaryInt = 0b1_1111_1111;
val precisionIntLiteral = 4i8;

// Unsigned
val unsigned: uint = 89; // <- 64 bit unsigned integer
// Other supported types are u8, u16, u32, u64. uint is just an alias for u64

// floats
val floatingPoint: float = 4.3; // <- 64 bit float
// Other supported types are f8, i16, f32, f64. float is just an alias for f64
val floatLiteral = 4.3f8;

// strings
val message: string = "Hello world!"; // <- Strings are heap-allocated object. Message is a small header to the memory on the heap
val message string = `${integer} is the magic number` // <- String templating
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
// Like strings, arrays are heap-allocated object. `myArray` is a small header to the memory on the heap
val myArray: float[] = [3.4, 5.6, 3.3];
val myOtherArray: Array<int> = [4, 5, 6];
val inferredTypeArray = ["hi", "ho"]; // type: Array<string>;

myArray[0]; // <- can be accessed with []
```

## Match expression

```matcha
// Matcha has no classical "if", except for early returning with the "return" and "leave" keyword, more on that later
val a = match (x) {
    0 => "zero",
    1 => "one",
    2, 3 => "two or three",
    else => "other", // Must be exhaustive
};

val b = match? (x) { // de-sugars into a "else => null" branch, therefore b has type string? (e.g. string|null)
    0 => "zero"
};
// Optional match with "else" branch is dis-allowed

val c = match { // subjectless match
    x == 0 => "zero",
    else => "other" // must also be exhaustive
};

val d = match? { // subjectless match that de-sugars to "else => null" branch
    x == 0 => "zero",
} ?? "coalesced to this string";
```

## Blocks

```matcha
val a = {
    10 // <- blocks are expressions that return the last expression without a ;   
};

val b = {
    leave 2 if cond; // <- leave keyword can be used for "early return" in blocks (expression blocks require a leave value)
    4
};

// leave <expr> is only allowed inside a value-producing context (a block used as an expression, or a loop used as an expression).
// leave; is only allowed in statement contexts

val c = outer: { // <- named blocks
    val c1 = inner: {
        leave :inner 123 if cond; // <- leaving named blocks
        43
    };
    42
};
```

## Looping

```matcha
loop { // <- infinite loop
    ...
    leave; // <- requires the leave keyword to terminate
}; // can go infinitely

val a = loop { // <- can be used as an expression but MUST have leave in that case
    ...
    leave 10;
}; // all control-flow paths must reach a leave when used as expression

val b = loop {
    leave 10 if condition; // <- pairs nicely with the "return ... if ..." / "leave ... if ..." sugar
    // Matcha has no regular "if" keyword that can be used for branching
};

val c = while (i < n) : (i += 1) {
    leave i if found(i);
} else -1; // <- when while is used with as an expression it requires an else

val p1 = for point in points {
  leave .{ x = point.x, y = point.y } if point.x == 0 and point.y == 0;
} else null;

val p2 = for {x, y} in points { // <- for with destructured item
  leave .{ x, y } if x == 0 and y == 0;
} else null;

val p3 = for point @ {x, y} in points { // <- for with whole and destructured item
  leave point if x == 0 and y == 0;
} else null;

val d = for (a, b) in (xs, ys) { // <- for with multiple lists
    leave a if a == b;
} else null;   // stops at shortest by definition

val e = for ({a, b}, y @ {c, d}) in (xs, ys) { // <- destructure in multi-list for
    leave y if a == c and b == d;
} else null;   // stops at shortest by definition


// leave always leaves the nearest block or loop,
// Can use labeled loops to decide what leave is leaving.
val d = outer: for ... {
    inner: loop {
        leave :outer value;
    };
};
```

## Structures

### Basics

```matcha
// Matcha does not have classes or inheritance, only structures
item User = structure {
    name: string;
    age: int;
    // Member variable with a default argument
    isCool: boolean = false;
};
// Items are compile time entities like structures, contracts, errors etc.
// They must be placed on the top-level of a file.

// Here is an example of instantiating an object that satisfies the `User` structure
// Matcha has a structural type system that forces you to specify a value for every field of a type.
val tom: User = .{
    name = "Tom",
    age = 32,
    // isCool can be omitted because it is false by default
};
// Values and variable are runtime entities.
// .{} is the object literal syntax.

// Because the type of `greg` is specified, the shorthand "dot" notation can be used here for object literals
var greg: User = .{
    name = "Greg",
    age = 23,
    isCool = true, // <- default value is overriden during instantiation
};
// variables can be re-assigned, values cannot
greg = .{
    name = "Actually not Greg at all",
    age = 32,
    // <- greg is no longer cool
};

val name = "Mario";
val age = 26;
val mario: User = .{ name, age }; // shorthand notation to prevent having to write name = name etc.

val alex = User { name, age }; // Syntactic sugar for defining an object that satisfies the `User` structure.
// The type of `alex` is inferred.

// Object can also be created with "unstructured" object literals.
// The type of `unstructuredObject` is inferred
val unstructuredObject = .{
    someKey = "someValue",
};
// objects can be de-constructed and the type of someKey can be inferred from unstructuredObject's type
val { someKey } = unstructuredObject;
```

### Memory allocation

```matcha
// For ergonomics, per default, structures are always handles to heap-allocated and GC-managed values
item User = structure {
    age: int;
    name: string;
};
val user = User { name = "Mario", age = 26 }; // <- `user` is only a handle that points to heap allocated data
val userB = user; <- userB and user now point to the same piece of memory

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

val userUpdateDtoReference = &userUpdateDto // Explicit heap allocation, type of `userUpdateDtoReference` is now Handle<UserUpdateDto>

userUpdateDtoReference.newAge = 42; // desugars to (*userUpdateDtoReference).newAge = 42 and mutates heap copy

val otherApply = function (dtoReference: Handle<UserUpdateDto>) {
    // ...
};
otherApply(userUpdateDtoReference); // <- passes only handle to `userUpdateDto`
otherApply(&userUpdateDto); // <- explicitly create handle and pass it to function
// structure types are already handles. No Handle<structure> allowed.
// Handle<T> only exists for inline types (boxing).u
```

#### Alternative with borrowing (which I don't like and only keep it here just in case)

Option B: Keep & as a borrow/view (points to the original), but then it must not escape

That’s Rust/Swift territory (even if you hide lifetimes). It can still be ergonomic, but it’s borrowing semantics, period.

If you go this route, you’d want:
- &x or view x → View<T> (readonly, can maybe escape)
- &mut x → MutView<T> (exclusive, cannot escape / cannot cross await)
- box x → Reference<T> (GC heap allocation)
This split is very conceptually clean.

### Contracts

```matcha
// Contracts are similar to interfaces in other programming langauges.
// They specify only the shape of an object but never their value.
// Inside a contract, self means the contract type, not the implementer. It desugars into the contract name
item Point = contract {
    x: int;
    y: int;
    distanceTo: (this: self, other:self) -> float;
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

```
item Vector = contract {
    x: float;
    y: float;
    distanceTo: (this: self, other:self) -> float;
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
    // The @ notation allows you to destructure only parts of an argument
    val asNormalized = function(this @ {x, y}: self): self {
        // Accessing a callable desugars into a function where receiver is passed as the first argument, hence we can omit the receiver in the surface language to achieve a nice, method-like syntax without having classes
        val length = this.length();
        // Since the return type can be inferred, we can use the shorthand dot notation
        return .(
            x / length,
            // Named parameter
            y = y / length,
        );
    };

    val projectedUp = function ({x}: self) {
        return .(
            x,
            0
        );
    };
};

// Instantiating a structure with a constructor requires you to use it.
val myVector = Vector(x = 3, y =7);
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