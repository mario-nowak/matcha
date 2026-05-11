item absolute(number: int): int = match {
    number < 0 => -number,
    else => number,
};

item countSort(array: int[]): int[] = {
    val n = array.length;

    // find the maximum element
    var maximum_element = array[0];
    var i = 0;
    while i < n : i = i+1 {
        if array[i] > maximum_element {
            maximum_element = array[i];
        }
    }

    // create and initialize count array
    val count_array: int[] = [];
    i = 0;
    while i <= maximum_element : i = i+1 {
        count_array.append(0);
    }

    // count frequency of each element
    i = 0;
    while i < n : i = i+1 {
        val index = array[i];
        count_array[index] = count_array[index] + 1;
    }

    // compute prefix sum
    i = 1;
    while i <= maximum_element : i = i+1 {
        count_array[i] = count_array[i] + count_array[i - 1];
    }

    // initialize output array
    val output_array: int[] = [];
    i = 0;
    while i < n : i = i+1 {
        output_array.append(0);
    }

    i = n - 1;
    while i >= 0 : i = i-1 {
        output_array[count_array[array[i]] - 1] = array[i];
        count_array[array[i]] = count_array[array[i]] - 1;
    }

    return output_array;
};

val file_content = readFile("aoc-2024-01-input.txt");
val rows = file_content.split("\n");

val first_list: int[] = [];
val second_list: int[] = [];

var row_index = 0;
while row_index < rows.length : row_index = row_index + 1 {
    val row = rows[row_index];
    val numbers = row.split("  ");
    first_list.append(numbers[0].trim().toInt());
    second_list.append(numbers[1].trim().toInt());
}

val sorted_first_list = countSort(first_list);
val sorted_second_list = countSort(second_list);

row_index = 0;
var distance = 0;
while row_index < rows.length : row_index = row_index + 1 {
    distance = distance + absolute(sorted_first_list[row_index] - sorted_second_list[row_index]);
}

// will print 1222801
printInt(distance);