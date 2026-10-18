item { hashPolynomial } = import "polynomial_hash.mt";
item { Measurement } = import "measurement.mt";
item { StationStatistics } = import "station_statistics.mt";

// A slot holds the index of a station in `StationTable.stations`.
item Slot = union { Empty, Station: int };

// A hash table with open addressing and linear probing. `stations` keeps the statistics in insertion order.
export item StationTable = structure {
    slots: Slot[];
    stations: StationStatistics[];

    // 1BRC has at most 10,000 stations, so 16,384 slots keep the table at most 61% full.
    item create(): StationTable = {
        val SLOT_COUNT = 16384;
        val slots: Slot[] = [];
        while slots.length < SLOT_COUNT {
            slots.append(.Empty);
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
            match self.slots[slot_index] {
                .Empty => {
                    self.slots[slot_index] = .Station(self.stations.length);
                    self.stations.append(StationStatistics.create(measurement.station, measurement.temperature_tenths));
                    return;
                },
                .Station(station_index) => {
                    if self.stations[station_index].name == measurement.station {
                        self.stations[station_index].record(measurement.temperature_tenths);
                        return;
                    }
                },
            };
            slot_index = (slot_index + 1) % self.slots.length;
        }
    };
};
