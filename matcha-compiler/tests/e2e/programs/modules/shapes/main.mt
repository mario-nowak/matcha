item { Point, Shape, scaled, describe } = import "geometry.mt";

item describeTwice(shape: Shape): string = describe(shape) + " / " + describe(shape);

// geometry.mt also defines a function named `double`, without exporting it.
item double(text: string): string = text + text;

val point: Point = .{
    x = 1,
    y = 2,
};
printString(describe(Shape.Dot(scaled(point))));
printString(describe(Shape.Empty));
printString(describeTwice(Shape.Empty));
printString(double("ab"));
