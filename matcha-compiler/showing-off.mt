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
    x: int;
    y: int;
};

item NestedPoint = structure {
    point1: Point;
    point2: Point;
};


var my_point = Point { x = 4, y = 5 };

my_point.y = 2;

var nested_point = NestedPoint {
    point1 = my_point,
    point2 = Point { x = 3, y = 6 },
};

printString("Printing points");
my_point.x = 110;
nested_point.point1.x = 330;
printInt(nested_point.point1.x);
printInt(nested_point.point2.y);

printString("Printing the while loop now");
while z < 10 {
    z = z + 1;
    printInt(z);
}
