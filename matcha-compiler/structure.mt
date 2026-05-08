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

item PointCluster = structure {
    points: Point[];

    item sum(self: PointCluster): Point = {
        var sum = Point.origin();
        var point_index = 0;
        while point_index < self.points.length : point_index = point_index + 1 {
            sum = sum.movedBy(self.points[point_index]);
        }

        return sum;
    };
};

val point_cluster = PointCluster {
    points = [
        Point { x =  3, y =  1, },
        Point { x = -3, y = -4, },
        Point { x = -8, y =  5, },
        Point { x =  9, y =  2, },
    ]
};

point_cluster.points.append(Point { x = 6, y = 7, });

val sum_point = point_cluster.sum();
sum_point.invert();
sum_point.print();
