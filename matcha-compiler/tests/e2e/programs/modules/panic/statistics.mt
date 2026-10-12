export item average(values: int[]): int = sum(values) / values.length;

item sum(values: int[]): int = {
    var total = 0;
    for value in values {
        total += value;
    }
    total
};
