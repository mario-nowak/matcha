item { StationStatistics } = import "station_statistics.mt";

// Sorts in place, byte by byte by name. Insertion sort is O(n²), which is fast enough for at most 10,000 stations.
export item sortStationsByName(stations: StationStatistics[]): unit = {
    var index = 1;
    while index < stations.length : index += 1 {
        val current = stations[index];
        var position = index;
        while position > 0 and stations[position - 1].name > current.name {
            stations[position] = stations[position - 1];
            position -= 1;
        }
        stations[position] = current;
    }
};
