// The One Billion Row Challenge (https://github.com/gunnarmorling/1brc).
// Reads lines like "Hamburg;12.0" and prints the minimum, mean, and maximum temperature per station, sorted by name:
// {Abha=-23.0/18.0/59.2, Abidjan=-16.2/26.0/67.3, ...}
//
// Run with: matcha run examples/one-billion-row-challenge/main.mt -- examples/one-billion-row-challenge/measurements.txt
// The 1BRC repository has a generator for larger inputs.

item { getArguments, printString } = import "builtin";

item { LineReader } = import "line_reader.mt";
item { Measurement } = import "measurement.mt";
item { StationStatistics } = import "station_statistics.mt";
item { StationTable } = import "station_table.mt";
item { sortStationsByName } = import "station_sorting.mt";

item main(): unit = {
    val arguments = getArguments();
    if arguments.length != 1 {
        printString("Usage: main <measurements file>");
        return;
    }

    val table = StationTable.create();
    val reader = LineReader.open(arguments[0]);
    while reader.hasNextLine() {
        val line = reader.nextLine();
        if line.length > 0 {
            table.record(Measurement.fromLine(line));
        }
    }

    sortStationsByName(table.stations);
    printString(formatResult(table.stations));
};

item formatResult(stations: StationStatistics[]): string = {
    val parts: string[] = [];
    for station in stations {
        parts.append(station.format());
    }

    return "{" + parts.join(", ") + "}";
};

main();
