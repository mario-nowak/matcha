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

## Hello world.

```matcha
```

## Primitive types

## Structures

### Basics

```matcha
// Matcha does not have classes or inheritance, only structures
item User = structure {
    // QUESTION: is it a good idea to let structures and contracts define the mutability of fields?
    val name: string;
    val age: int;
    // Member variable with a default argument
    val isCool: boolean = false;
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

// variables can be re-assigned, values cannot
// Because the type of `greg` is specified, the shorthand "dot" notation can be used here for object literals
var greg: User = .{
    name = "Greg",
    age = 23,
    isCool = true, // <- default value is overriden during instantiation
};

greg = .{
    name = "Actually not Greg at all",
    age = 32,
    // <- greg is no longer cool
};

val name = "Mario";
val age = 26;
val mario: User = .{name, age}; // shorthand notation to prevent having to write name = name etc.

val alex = User {name, age}; // Syntactic sugar for defining an object that satisfies the `User` structure.
// The type of `alex` is inferred.

// Object can also be created with "unstructured" object literals.
// The type of `unstructuredObject` is inferred
val unstructuredObject = .{
    someKey = "someValue",
};
// objects can be de-constructed and the type of someKey can be inferred from unstructuredObject's type
val { someKey } = unstructuredObject;
```

### Contracts

```matcha
// Contracts are similar to interfaces in other programming langauges.
// They specify only the shape of an object but never their value.
// QUESTION: Does it make sense for contracts to specify the mutability of fields?
// Inside a contract, self means the contract type, not the implementer. It desugars into the contract name
item Point = contract {
    var x: int;
    var y: int;
    val distanceTo: (this: self, other:self) -> float;
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
val computeDistanceBetween = function (a: Point, b: Point): float {
    return a.distanceTo(b);
};

// These distances won't be the same
val distanceFromSomePointToSomeOtherPoint = computeDistanceBetween(somePoint, someOtherPoint);
val distanceFromSomeOtherPointToSomePoint = computeDistanceBetween(someOtherPoint, somePoint);
// This is an example of runtime polymorphism in matcha: depending on the actual point, the right
// distanceTo function is used.

// Structures can satisfy a contract.
item EuclideanVector = structure satisfies Point {
    // `x` and `y` are already specified on the `Point` contract.
    // The contract's `distanceTo` function receives an immutable default value for a `EuclideanVector`
    val distanceTo = function (this: self, other: self): float {
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
    val x: float;
    val y: float;
    val distanceTo: (this: self, other:self) -> float;
};

item StrangeVector = structure satisfies Vector {
    val distanceTo = function (this: self, other: self): float {
        return (other.x - this.x)**2 + (other.y - this.y)**2;
    };
};

item EuclideanVector = nominal structure satisfies Vector {
    val distanceTo = function (this: self, other: self): float {
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
    val coolAttribute: string;

    // Nominal structures can have private fields
    private val secret: string;

    // Both nominal and non-nominal structures can have a constructor but it must be used if defined
    constructor (
        // Constructor property promotion
        public val firstName: string,
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
    val x: float;
    val y: float;

    val length: (this: self) -> float;
    val lengthSquared: (this: self) -> float;
    val lengthCubed: (this: self) -> float;
    val addedTo: (this: self, other: self) -> self;
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
    val cachedLength: float;
    
    // A structure can have a constructor that handles initialization
    constructor (
        // Constructor property promotion to satisfy interface
        public val x: float,
        public val y: float,
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