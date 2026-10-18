item { parseTemperatureTenths } = import "temperature.mt";

export item Measurement = structure {
    station: string;
    temperature_tenths: int;

    // A line looks like "Hamburg;12.0". A station name can contain any byte except ';', so the search for the separator
    // starts at the end, where the temperature has at most five bytes.
    item fromLine(line: string): Measurement = {
        val SEMICOLON_BYTE = 59;
        var separator_index = line.length - 1;
        while line.getByteAt(separator_index) != SEMICOLON_BYTE {
            separator_index -= 1;
        }

        return .{
            station = line.slice(0, separator_index),
            temperature_tenths = parseTemperatureTenths(line.slice(separator_index + 1, line.length)),
        };
    };
};
