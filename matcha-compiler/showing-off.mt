val x = 3;
var y: int = 3;

y = y + 1;

printInt(y);

printString("Hello world");

item addOne(x: int): int = x + 1;

printInt(addOne(y));

var z = {
    val hi = 4;
    hi
};
printInt(z);

item complexFunction(x: int): int = {
    if x == 0 {
        printString("Is zero");
        return x;
    }

    x + 1
};

val aaa = complexFunction(1);
printInt(aaa);

val is_happy = true;

item Point = structure {
    x: int,
    y: int,
};




val my_point = Point { x = 4, y = 5 };

while z < 10 {
    z = z + 1;
    printInt(z);
}