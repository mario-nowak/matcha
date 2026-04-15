item myFunction(parameter: int): int = match parameter {
    0 => 1,
    1 => 0,
    else => parameter,
};


printInt(myFunction(0));
printInt(myFunction(1));
printInt(myFunction(2));

val is_happy = true;

match {
    is_happy => printString("I'm pretty happy"),
    else => printString("I'm not that happy"),
};


printString(match {
    is_happy => "I'm pretty happy",
    else => "I'm not that happy",
});

printString(match {
    is_happy => {
        printString("Some side-effect");
        "I'm pretty happy"
    },
    else => "I'm not that happy",
});

match (is_happy) {
    true => printString("Exhaustive happy"),
    false => printString("Exhaustive sad"),
};