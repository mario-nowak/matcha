// The One Million Row Challenge: a small version of the One Billion Row Challenge (https://github.com/gunnarmorling/1brc).
// Reads lines like "Hamburg;12.0" and prints the minimum, mean, and maximum temperature per station, sorted by name:
// {Abha=-23.0/18.0/59.2, Abidjan=-16.2/26.0/67.3, ...}
//
// Run with: matcha run examples/one-million-row-challenge/main.mt -- examples/one-million-row-challenge/measurements.txt
// The 1BRC repository has a generator for larger inputs.

item { getArguments, readFileChunk, printString } = import "builtin";

item { parseMeasurement } = import "measurement.mt";
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
    recordMeasurements(table, arguments[0]);
    sortStationsByName(table.stations);
    printString(formatResult(table.stations));
};

// Reads the file in chunks, so memory use stays the same for any file size. A chunk usually ends inside a line, so the
// incomplete last line is carried over to the next chunk.
item recordMeasurements(table: StationTable, path: string): unit = {
    val CHUNK_SIZE = 1048576;
    var offset = 0;
    var leftover = "";
    loop {
        val chunk = readFileChunk(path, offset, CHUNK_SIZE);
        if chunk.length == 0 {
            leave;
        }
        offset += chunk.length;

        val text = leftover + chunk;
        val lines = text.split("\n");
        var index = 0;
        while index < lines.length - 1 : index += 1 {
            recordLine(table, lines[index]);
        }
        leftover = lines[lines.length - 1];
    }
    recordLine(table, leftover);
};

item recordLine(table: StationTable, line: string): unit = {
    if line.length > 0 {
        val measurement = parseMeasurement(line);
        table.record(measurement.station, measurement.temperatureInTenths);
    }
};

item formatResult(stations: StationStatistics[]): string = {
    val parts: string[] = [];
    for station in stations {
        parts.append(station.format());
    }

    return "{" + parts.join(", ") + "}";
};

main();
