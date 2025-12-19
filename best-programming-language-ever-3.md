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
    ShopNotEligibleForUsageReportSubmissionError,
    ShopUuidDoesNotMatchPluginLicenseError,
    ShopUuidDoesNotMatch,
};

item UsageReportService = structure {

    val registerUsageReportsForShop = async function (
        this: self,
        {
            shopUuid: string,
            usageReportPayloads: UsageReportPayload[],
            pluginLicenseUuid: string? = null
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

        val usageReportIdentifiers = usageReportPayloads:map((usageReportPayload) => usageReportPayload.uuid);
    };
};
```

# Matcha specification

```matcha
// File user.mt

// `items` are compile time definitions like contracts, errors, structures etc.
// they must be on the top-level of a file
// Matcha does not have classes, only structures (more on that later)
item User = structure {
    val name: string;
    val age: int;
    // Member variable with a default argument
    val isCool: boolean = false;
};

// values and variable are runtime entities
// Instantiation of a user: (the type of tom is now inferred)
// This "raw" instantiation must provide all uninitialized values
val tom = User {
    name = "Tom",
    age = 32,
    // isCool can be omitted because it is false by default
};

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


// File point.mt
// Contracts are similar to interfaces in other programming langauges.
// They specify only what fields an object but never their value.
// Structures can satisfy a contract.
item Point = contract {
    var x: int;
    var y: int;
    val distanceTo: (this: self, other:self) -> float;
};

// Values can be of a contract type
val somePoint: Point = .{
    x = 3,
    y = 7,
    // but they need to satisfy the contract, even if it means providing implementation details
    distanceTo = function (this: self, other: self): float {
        return ((other.x - this.x)**2 + (other.y - this.y)**2)**0.5;
    };
};

// Object can also be created with unstructured object literals
val unstructuredObject = .{
    someKey = "someValue",
};
// objects can be de-constructed and the type of someKey can be inferred from unstructuredObject's type
val { someKey } = unstructuredObject;


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