item Point = structure {
    x: int;
    y: int;

    item movedBy(self: Point, other: Point): Point = Point {
        x = self.x + other.x,
        y = self.y + other.y,
    };
};

item PointHolder = structure {
    point_1: Point;
    point_2: Point;
};

item someFunction(): int = 2;

val point = Point {
    x = 3,
    y = 1,
};

var other_point = Point {
    x = 1,
    y = 4,
};

val result_point = Point.movedBy(point, other_point);

var x = 2;
