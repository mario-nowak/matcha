item incrementArray(array: int[]): unit = {
    var i = 0;
    while i < array.length : i = i + 1 {
        array[i] = array[i] + 1;
    }
};

item sumArray(array: int[]): int = {
    var sum = 0;
    var i = 0;
    while i < array.length : i = i + 1 {
        sum = sum + array[i];
    }

    return sum;
};

val my_array = [
    1, 2, 3,
];
incrementArray(my_array);
var i = 0;
while i < my_array.length : i = i + 1 {
    printInt(my_array[i]);
}

val sum = sumArray(my_array);
printInt(sum);