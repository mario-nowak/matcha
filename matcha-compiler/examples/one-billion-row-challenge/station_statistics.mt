item { formatTemperatureTenths, divideRoundingHalfUp } = import "temperature.mt";

export item StationStatistics = structure {
    name: string;
    temperature_tenths_minimum: int;
    temperature_tenths_maximum: int;
    temperature_tenths_sum: int;
    measurement_count: int;

    item create(name: string, temperature_tenths: int): StationStatistics = .{
        name = name,
        temperature_tenths_minimum = temperature_tenths,
        temperature_tenths_maximum = temperature_tenths,
        temperature_tenths_sum = temperature_tenths,
        measurement_count = 1,
    };

    item record(self: StationStatistics, temperature_tenths: int): unit = {
        if temperature_tenths < self.temperature_tenths_minimum {
            self.temperature_tenths_minimum = temperature_tenths;
        }
        if temperature_tenths > self.temperature_tenths_maximum {
            self.temperature_tenths_maximum = temperature_tenths;
        }
        self.temperature_tenths_sum += temperature_tenths;
        self.measurement_count += 1;
    };

    // Formats "Hamburg=-23.0/18.0/59.2", which is minimum/mean/maximum.
    item format(self: StationStatistics): string = self.name
        + "="
        + formatTemperatureTenths(self.temperature_tenths_minimum)
        + "/"
        + formatTemperatureTenths(divideRoundingHalfUp(self.temperature_tenths_sum, self.measurement_count))
        + "/"
        + formatTemperatureTenths(self.temperature_tenths_maximum);
};
