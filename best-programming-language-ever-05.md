# V1

bool booleanValue = true
function foo = (int value): int -> value * 2
type myCustomType = (int, int) -> int

class myCustomClass = {

    public constructor(
        private readonly int constructorMember
    )

    private string normalStringMember = "hello!"

    public function somePublicFunction = (int value): int -> {
        this.constructorMember + value
    }
}



interface myCustomInterface = 

var instance = myCustomClass(constructorMember = 3)

instance.somePublicFunction(2)

---

let booleanValue: bool = true
let foo = (value: int): int -> value * 2
let functionWithoutReturnType = (value: int) -> value * 3

// Define a type 
let myCustomType = (int, int) -> int

// Define a class
let MyCustomClass = class {

    public constructor(
        private readonly int constructorMember
    )

    private string normalStringMember = "hello!"

    public function somePublicFunction = (int value): int -> {
        this.constructorMember + value
    }
}

interface myCustomInterface = interface {
    someMember: int;
    someOtherMember: (value: MyCustomClass): int
}

var instance = myCustomClass(constructorMember = 3)
instance.somePublicFunction(2)

# V2

// Defining a primitive value
let booleanValue: bool = true

// Defining a mutable variable with an inferred type
var mutableBoolean = true



// Defining an array
let myArray: Array = [1, 2, 3]



// Defining an object (shorthand for defining and instantiating an anonymous class)
let myObject = {
    x: int = 3;
    y: bool = false;
    // inferred type
    z = 4;
}

// Object deconstruction
let { x, y, z } = myObject

// Defining a function
let foo = (value: int): int -> value * 2
let functionWithInferredReturnType = (value: int) -> value * 3

// Define a type 
let myCustomType = (int, int) -> int

// Define a class
let MyCustomClass = class {

    public constructor(
        private readonly constructorMember: int
    )

    private normalStringMember: string = "hello!"

    public somePublicFunction = (value: int): int -> {
        this.constructorMember + value
    }
}

var instance = myCustomClass(constructorMember = 3)

instance.somePublicFunction(2)

// Define an interface
let myCustomInterface = interface {
    someMember: int;
    someOtherMember: (MyCustomClass) -> int;
}

# V3
// --- Basic features ---

// Defining a value
let myInt: int = 1
let myDecimal: decimal = 1.0
// TODO: are strings immutable? Are strings passed by value or by reference?
let myString: string = "Hello, world!"
let booleanValue: bool = true
// Defining a mutable variable with an inferred type
var mutableBoolean = true

// Defining an array
// TODO: are arrays passed by value or by reference?
let myArray = [1, 2, 3]

// --- Blocks ---

// A code block is an expression that evaluates to the last expression in that block
let outsideVar = 1
{
    // firstVar and secondVar are scoped to the block
    let firstVar = 2
    let secondVar = 3
    // Values and variables defined before the block are accessible in the block
    let thirdVar = outsideVar + firstVar + secondVar
}

let evaluationOfBlock = {
    let firstVar = 1
    let secondVar = 2

    firstVar + secondVar
}


// --- Functions ---

// Defining a function with a return type
let foo = (value: int): int -> value * 2
// Defining a function with an inferred return type
let functionWithInferredReturnType = (value: int) -> value * 3
// Defining a function with a default value
let functionWithDefaultValue = (value: int = 1) -> value * 2
// Defining a function with a variadic parameter
let functionWithVariadicParameter = (value: int, ...rest: int[]) -> value * 2

// Creating a function with a more complex block binds the parameters to the block
let complexFunction = (value: int) -> {
    let firstVar = 1
    let secondVar = 2

    firstVar + secondVar
}

// The return keyword is optional
let returnKeywordIsOptional = (value: int) -> {
    return value * 2
}

// --- Closures ---

// TODO: Closures are functions that capture the environment in which they are defined


// --- Types ---

// Define a type 
// Types are used to create type aliases, here a function that takes two ints and returns an int
let myCustomFunctionType = type (int, int) -> int

// --- Control flow ---

// If expression
let booleanValue = true
if booleanValue {
    console.writeLine("The boolean value is true")
} else {
    console.writeLine("The boolean value is false")
}

let ifExpressionValue = if booleanValue {
    "The boolean value is true"
} else {
    "The boolean value is false"
}

let booleanValue2 = false
let ifElseExpressionValue = if booleanValue {
    "The boolean value is true"
} else if booleanValue2 {
    "The boolean value is false"
} else {
    "The boolean value is neither true nor false"
}

// --- Classes ---

// Define a class
let MyCustomClass = class {
    public constructor(
        private readonly constructorMember: int
    )

    private normalStringMember: string = "hello!"

    public somePublicFunction = (value: int): int -> {
        this.constructorMember + value
    }
}
var instance = myCustomClass(constructorMember = 3)
instance.somePublicFunction(2)

// Special syntaxes
@SomeDecorator 
let moreSpecialClass

// --- Object literals ---

// Defining an object (shorthand for defining and instantiating an anonymous class)
let myObject = {
    x: int = 3;
    y: bool = false;
    // inferred type
    z = 4;
}
// Object deconstruction
let { x, y, z } = myObject

// --- Interfaces ---

// Define an interface
// Interfaces are used to define a contract that a class must implement
let myCustomInterface = interface {
    someMember: int;
    someOtherMember: (MyCustomClass) -> int;
}

// --- Pattern matching ---
let Point = sealed interface
// Algebraic data types
let Point2D = case class extends Point { x: decimal, y: decimal }
let Point3D = case class extends Point { x: decimal, y: decimal, z: decimal }

let point2d = Point2D(x = 1, y = 2)
let squaredLength = match point2d {
    case Point2D (x, y) { x**2 * y**2 }
    case Point3D (x, y, z) { x**2 * y **2 * z**2 }
}

// Since match is an expression, it can be used as a function
let matchAsFunction = (point: Point) -> match point {
    case Point2D (x, y) { x**2 * y**2 }
    case Point3D (x, y, z) { x**2 * y **2 * z**2 }
}


// --- Pipe operator ---

// --- Async/await ---

let asyncFunction = async () -> {
    await someAsyncOperation()

    return "Hello, world!"
}

// -- Writing to console ---

console.writeLine("Hi! How are you doing?")

What do you think? Please be critical and point out inconsistencies or dump ideas.

# Mutability

// --- Basic features ---

// Defining a value
let myInt: int = 1
let myDecimal: decimal = 1.0
// TODO: are strings immutable? Are strings passed by value or by reference?
let myString: string = "Hello, world!"
let booleanValue: bool = true
// To create a re-assignable variable, use the var keyword
var mutableBoolean = true

// Defining an array
// TODO: are arrays passed by value or by reference?
let myArray = [1, 2, 3]

// Variables are immutable by default, to create a mutable variable, use the mutable keyword
let mutableInt = mutable 1
