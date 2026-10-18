item { hashPolynomial } = import "polynomial_hash.mt";
item { Measurement } = import "measurement.mt";
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

    item record(self: StationTable, measurement: Measurement): unit = {
        var slot_index = hashPolynomial(measurement.station) % self.slots.length;
        loop {
            val station_index = self.slots[slot_index];
            if station_index == -1 {
                self.slots[slot_index] = self.stations.length;
                self.stations.append(StationStatistics.create(measurement.station, measurement.temperature_tenths));
                return;
            }
            if self.stations[station_index].name == measurement.station {
                self.stations[station_index].record(measurement.temperature_tenths);
                return;
            }
            slot_index = (slot_index + 1) % self.slots.length;
        }
    };
};
