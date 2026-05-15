item Point = structure {
    x: int;
    y: int;

    item origin(): Point = .{
        x = 0,
        y = 0,
    };

    item invert(self: Point): unit = {
        self.x *= -1;
        self.y *= -1;
    };

    item movedBy(self: Point, other: Point): Point = .{
        x = self.x + other.x,
        y = self.y + other.y,
    };

    item length(self: Point): int = self.x * self.x + self.y * self.y;

    item print(self: Point): unit = printString(
        "Point { x = " + self.x.toString() + ", y = " + self.y.toString() + " } (length: " + self.length().toString() + ")"
    );
};

val origin = Point.origin();
val offset: Point = .{
    x = 3,
    y = 6,
};
val other_point = origin.movedBy(offset);
other_point.invert();
other_point.print();
