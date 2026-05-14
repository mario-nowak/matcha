// Matcha is a small compiled language for command-line programs and data-heavy services.
// Its main ideas are exhaustive `match`, explicit data modeling, and code that stays readable
// as decision logic grows.
//
// This file is a tour of the current language surface:
// 1. values and built-in types
// 2. control flow and loops
// 3. functions
// 4. structures and methods

// # Basics

// ## Defining values
// `val` declares a binding-immutable value. Re-assigning `the_answer` would be a compile-time error.
val the_answer: int = 42;

// Type annotations are optional when the compiler can infer the type from the expression.
val first_prime = 2;

// `var` declares a binding-mutable variable.
var i_can_change = 4;
// That means re-assignment is allowed.
i_can_change += 1;


// ## Types
// Matcha currently has the built-in types `int`, `boolean`, and `string`.
val this_is_an_int: int = 3;
val this_is_a_boolean: boolean = true;
val this_is_a_string: string = "hello world";

// ### Ints
// Ints support addition, subtraction, negation, and multiplication.
val complex_computation = (3 + 4) * -(8 - 2);
// Ints can be cast to strings.
val int_as_string = 3.toString();

// ### Booleans
// Booleans support the `and`, `or`, and `not` operators.
val complex_condition = true and (not false or true);

// ### Strings
// Strings are immutable references to string data in memory.
val my_string = "hello";
val my_other_string = my_string; // `my_other_string` and `my_string` point to the same string data.
// Strings can be concatenated with the `+` operator.
val hello_world = "hello" + " " + "world";
// Strings can be trimmed.
val trimmed_string = "    hello    ".trim();
// Strings can be cast to ints.
val string_as_int = "1337".toInt(); // `toInt` will panic for invalid strings.
// Strings also have a byte-length field.
val string_length = my_string.length;

// ### Arrays
// Arrays are small headers that store the length and a pointer to the underlying data.
val my_int_array: int[] = [1, 2, 3];
// Assigning an array copies the header, so both bindings still refer to the same array data.
val my_second_array = my_int_array;
val inferred_type_array = [4, 5, 6]; // The type is inferred as `int[]`.
val empty_array: string[] = []; // Empty arrays require an explicit type annotation.
// Arrays can be grown using `append`. Mutating through one alias is visible through the other.
my_second_array.append(4);
// Arrays have a `length` field.
val array_length = my_int_array.length; // This is 4 now.


// # Control flow

// ## Blocks
// Every block introduces a new scope.
{
    val defined_in_block = 3;
}
// `defined_in_block` does not exist outside the block.
// Blocks are also expressions. The final expression, without a trailing semicolon, becomes the value.
val is_happy = {
    val has_eaten = true;
    val had_good_sleep = true;

    has_eaten and had_good_sleep // <- no semicolon here
};


// ## Branching
// `if` can be used as a statement.
var confirmed_is_happy = false;
if is_happy {
    confirmed_is_happy = true;
}
// `if` can also be used as an expression.
val has_time = true;
val message = if is_happy and has_time {
    "is really happy"
} else {
    "is only happy"
};
// Matcha does not have `else if`. For larger branching logic, use `match`.

// ### Match expression
// `match` is Matcha's main branching construct.
// For closed value sets like `boolean`, matches must be exhaustive.
val matched_message = match is_happy {
    true => "they are happy",
    false => "they are not happy",
};

// Blocks are expressions too, so match arms can contain multiple statements when needed.
var happy_people_counter = 0;
var not_happy_people_counter = 0;
match is_happy {
    true => {
        happy_people_counter += 1;
    },
    false => {
        not_happy_people_counter += 1;
    },
};

// For open value sets like `int` or `string`, add an `else` arm.
val other_matched_message = match happy_people_counter {
    0 => "No people are happy",
    1 => "One person is happy",
    2 => "Two people are happy",
    else => "More than two people are happy",
};

// There is also a subjectless `match` form for complex decision trees.
val status = match {
    happy_people_counter < 0 => "Something went wrong",
    happy_people_counter == 0 and not_happy_people_counter == 0 => "No people there",
    happy_people_counter > 0 and not_happy_people_counter == 0 => "Only happy people",
    happy_people_counter == 0 and not_happy_people_counter > 0 => "Only non-happy people",
    happy_people_counter > 0 and not_happy_people_counter > 0 => "Mixed happiness",
    else => "Unknown status",
};

// ## Loops
// Matcha has three loop constructs.
// First is a headless loop that runs forever until you explicitly `leave`.
var i = 0;
loop {
    if i >= 9 {
        leave;
    }
    i += 1;
}

// Second is `while`.
i = 0;
var on = true;
while i <= 9 {
    on = not on;
    i += 1;
}
// `while` also supports an optional update assignment after the condition.
while i <= 9 : i += 1 {
    on = not on;
}

// Finally, there is `for` iteration over arrays.
var sum = 0;
val entries = [2, 3, 4, 5];
for entry in entries {
    sum += entry;
}

// # Functions
// ## Built-in functions
// Matcha currently has a small built-in standard library.
// `printInt` prints an int.
printInt(the_answer);

// `printString` prints a string.
printString(hello_world);

// `getArguments` returns the arguments passed to the compiled binary.
val arguments = getArguments();

// `readFile` reads the contents of a file.
if arguments.length >= 1 {
    val file_content = readFile(arguments[0]);
}

// `readLine` reads a single line from stdin.
printString("Say: hi");
loop {
    val answer = readLine();
    match answer.trim() {
        "hi" => {
            printString("Well done!");
            leave;
        },
        "Hi!" => printString("Try a bit less enthusiastic..."),
        "hello" => printString("Almost! But not quite..."),
        else => printString("Wrong answer! Try again!"),
    };
}


// ## User-defined functions
// Functions and structures are compile-time items. They are declared with `item`.
// That keeps the naming pattern consistent: `val` names a runtime value, `var` names a runtime
// variable, and `item` names a compile-time concept.
// The general shape is:
// item <NAME> = <THING_BEING_DEFINED>;
//
// For functions specifically, the shape is:
// item <FUNCTION_NAME>(<PARAMETER>: <TYPE>, ...): <RETURN_TYPE> = <EXPRESSION>;
//
// Function bodies are expressions. For tiny functions, that expression can be a single value.
item identity(x: int): int = x;
// `identity` evaluates to `x`.
// For multi-step work, use a block body. A block is still an expression, and `return` can make
// the final result explicit.
item sumNumbers(numbers: int[]): int = {
    var sum = 0;
    for number in numbers {
        sum += number;
    }

    return sum;
};
// More examples:
item absolute(number: int): int = match {
    number < 0 => -number,
    else => number,
};

item printStatus(code: int): unit = match code {
    0 => printString("No errors"),
    else => printString("Encountered error code: " + code.toString()),
};


// # Structures
// Structures group fields under a named type.
// Like arrays, a structure value is a small header pointing at GC-managed data.
item Person = structure {
    name: string;
    age: int;
};

// Construct a structure by naming its fields.
val person = Person {
    name = "John Doe",
    age = 32,
};

// When the type is already known, `.{}` is a shorter construction form.
val other_person: Person = .{
    name = "Jack Jackson",
    age = 23,
};

// Assigning a structure copies the header, not the underlying object.
// Mutating through one alias is visible through the other.
val person_alias = person;
person_alias.age += 1;
printInt(person.age); // Prints 33.

// Structures can also define functions inside the type body.
item Point = structure {
    x: int;
    y: int;

    // Functions without `self` behave like namespaced factory or helper functions.
    item origin(): Point = .{
        x = 0,
        y = 0,
    };

    // A function that takes `self` can mutate the current structure value.
    item invert(self: Point): unit = {
        self.x *= -1;
        self.y *= -1;
    };

    // Methods can also return a new structure value instead of mutating in place.
    item movedBy(self: Point, other: Point): Point = .{
        x = self.x + other.x,
        y = self.y + other.y,
    };

    item length(self: Point): int = self.x * self.x + self.y * self.y;

    item print(self: Point): unit = printString(
        "Point { x = " + self.x.toString() + ", y = " + self.y.toString() + " } (length: " + self.length().toString() + ")"
    );
};

// Call a structure function through the type name.
val origin = Point.origin();
val offset: Point = .{
    x = 3,
    y = 6,
};

// If a function takes `self`, it can also be called with instance syntax.
// `origin.movedBy(offset)` desugars to `Point.movedBy(origin, offset)`.
val other_point = origin.movedBy(offset);
other_point.invert();

other_point.print();
