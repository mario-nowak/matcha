item { StationStatistics } = import "station_statistics.mt";

// A hash table with open addressing and linear probing. A slot holds the index of a station in `stations`, or -1 when
// it is empty. `stations` keeps the statistics in insertion order.
export item StationTable = structure {
    slots: int[];
    stations: StationStatistics[];

    // 1BRC has at most 10,000 stations, so 16,384 slots keep the table at most 61% full.
    item create(): StationTable = {
        val SLOT_COUNT = 16384;
        val slots: int[] = [];
        while slots.length < SLOT_COUNT {
            slots.append(-1);
        }
        val stations: StationStatistics[] = [];

        return .{
            slots = slots,
            stations = stations,
        };
    };

    item record(self: StationTable, station: string, temperature_in_tenths: int): unit = {
        var slot_index = hashStation(station) % self.slots.length;
        loop {
            val station_index = self.slots[slot_index];
            if station_index == -1 {
                self.slots[slot_index] = self.stations.length;
                self.stations.append(StationStatistics.create(station, temperature_in_tenths));
                return;
            }
            if self.stations[station_index].name == station {
                self.stations[station_index].record(temperature_in_tenths);
                return;
            }
            slot_index = (slot_index + 1) % self.slots.length;
        }
    };
};

// A polynomial hash over the bytes. The modulo after every step keeps the value far below the int range.
item hashStation(station: string): int = {
    var hash = 0;
    var index = 0;
    while index < station.length : index += 1 {
        hash = (hash * 31 + station.getByteAt(index)) % 1000003;
    }

    return hash;
};
