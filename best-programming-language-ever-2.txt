// --- Comments

// Single line comment
/// Documentation comment.

// --- Defining values
// Values are immutable, the cannot be re-assigned

let myInt: int = 1;
let myFloat: float = 4.4; // Still uncertain how to call these instead of "float" because I really hate that name
let myBoolean: boolean = true; // Still uncertain how to call these instead because I hate "boolean"

// --- Defining variables
// Variables are mutable and can be re-assigned

var myMutableInt: int = 5;
myMutableInt = myMutableInt + 3; // This is valid

// --- Primitive data types

// --- Blocks

// Blocks are expression that return the last expression in that block
let a = 4;
let b = 7;
{
    let scoped = a + 4;
    b - scoped;
};

// --- Functions

// In matcha, there are no definitions, only declarations.
// Declaring a function
let myCoolFunction = (x: int, y:int): int => {
    return x * 2 + y;
};
// The return keyword is optional since
let myCoolFunctionWithoutExplicitReturn = (x: int, y:int): int => {
    x * 2 + y;
};
// And since the body block of the function only has one expression, we can omit the block entirely
let myCoolLightweightFunction = (x: int, y: int): int => x * 2 + y;

// Using said function
let result = myCoolFunction(3, 4);

// --- Pipe operator

let x = 4;
let resultOfPipe = x |> myCoolFunction(4); // Same as myCoolFunction(x, 4);

let functionUsingAPipe = (x: int) => x |> myCoolFunction(4);

// --- Structures

let Vector = structure {
    x: float;
    y: float;

    length = (self: Vector) => self.x**2 + self.y**2;

    asNormalized = (self: Vector): Vector => {
        let length = self:length();
        
        return Vector {
            x = self.x / length;
            y = self.y / length;
        };
    };

    asScaled = (self: Vector, scale: float): Vector => Vector {
        x = self.x * scale;
        y = self.y * scale;
    };

    dot = (leftVector: Vector, rightVector: Vector): float => {
        leftVector.x * rightVector.x + leftVector.y * rightVector.y;
    };
};

// Instantiation of vector
let vector = Vector {
    x = 4.4;
    y = 5.6;
};

// Shorthand
let otherVector: Vector = .{
    x = 4.4;
    y = 5.6;
};

// "Plain" member function invocation
var normalized = vector.asNormalized(vector);
// Member function invocation with pipe operator (not convenient yet but we're getting there)
normalized = vector |> vector.asNormalized();
// Idiomatic member function invocation: Syntactic sugar for calling the pipe operator on a member variable
normalized = vector:asNormalized(); // => same as `vector |> vector.asNormalized()` => same as `vector.asNormalized(vector)`

// Which allows us to do the same as invoking "methods" in many other programming languages
let twiceAsLongVector = normalized:asScaled(2);
let dotProductResult = vector:dot(otherVector);

// --- Pointers and memory

// TODO: Don't know how to design allocation syntax yet
// allocate memory for an int
let aPointer: Pointer<int> = allocate(int, 1);
// De-reference pointer by loading the value
var aValue = aPointer:load();
aValue = aValue + 1;
// Store a new value at the pointer's address
aPointer:store(aValue);

let vector: Pointer<Vector> = allocate(Vector, 1):store(Vector {
    x = 3;
    y = 6;
});
let normalized: Pointer<Vector> = allocate(Vector, 1):store(vector:load():asNormalized());

// --- Arrays

// --- Optionality

// --- Control flow

// --- --- Match expressions
// Matcha has no if-else, the only branching control flow structure is the match!
let x = 5;
match x {
    4 -> print("x is 4"), // cases are separated with a comma
    5 -> print("x is 5"),
    else -> print("x is neither 4 nor 5") // match statements must be exhaustive. _ is the shorthand for covering any remaining cases
};

// match is an expression!
let y = match x {
    4 -> true,
    5 -> false,
    else -> false
};

// match can be used without a subject
let z = match {
    y == true -> false,
    y == false -> true,
    else -> false,
}

// match? allows you to omit the _ branch and returns null for it
let optionalMatchExample = (x: int): int => {
    match? x {
        0 -> return 0;
    };

    return 1 / x;
}
// More lightweight notation:
let optionalMatchExample2 = match x {
    x != 0 -> 1 / x,
    else -> 0,
}

// --- --- Loop

var i = 0;
loop {
    match? {
        i % 2 == 0 -> print("i is even"),
        i == 10 -> break,
    };

    i = i + 1;
}

// --- Errors ---