item Point = structure {
    x: int;
    y: int;

    item movedBy(self: Point, other: Point): Point = Point {
        x = self.x + other.x,
        y = self.y + other.y,
    };

    item invert(self: Point): unit = {
        self.x = -self.x;
        self.y = -self.y;
    };

    item origin(): Point = Point {
        x = 0,
        y = 0,
    };

    item print(self: Point): unit = {
        printInt(self.x);
        printInt(self.y);
    };
};

item PointHolder = structure {
    point_1: Point;
    point_2: Point;
};

val point = Point {
    x = 3,
    y = 1,
};

var other_point = Point {
    x = 1,
    y = 4,
};

val result_point = Point.origin().movedBy(other_point);
result_point.print();
result_point.invert();
result_point.print();
