export item Point = structure {
    x: int;
    y: int;

    item length(self: Point): int = self.x * self.x + self.y * self.y;
};

export item Shape = union {
    Dot: Point,
    Empty,
};

item double(value: int): int = value * 2;

export item scaled(point: Point): Point = .{
    x = double(point.x),
    y = double(point.y),
};

export item describe(shape: Shape): string = match shape {
    .Dot(point) => "dot with length " + point.length().toString(),
    .Empty => "empty",
};
