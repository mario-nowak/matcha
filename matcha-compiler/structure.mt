item Point = structure {
    x: int,
    y: int,
};

item PointHolder = structure {
    point_1: Point,
    point_2: Point,
};

item someFunction(): int = 2;

val point = Point {
    x = 3,
    y = 1,
};

var x = 2;