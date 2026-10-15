item { formatTenths, divideRoundingHalfUp } = import "temperature.mt";

export item StationStatistics = structure {
    name: string;
    minimumInTenths: int;
    maximumInTenths: int;
    sumInTenths: int;
    count: int;

    item create(name: string, temperature_in_tenths: int): StationStatistics = .{
        name = name,
        minimumInTenths = temperature_in_tenths,
        maximumInTenths = temperature_in_tenths,
        sumInTenths = temperature_in_tenths,
        count = 1,
    };

    item record(self: StationStatistics, temperature_in_tenths: int): unit = {
        if temperature_in_tenths < self.minimumInTenths {
            self.minimumInTenths = temperature_in_tenths;
        }
        if temperature_in_tenths > self.maximumInTenths {
            self.maximumInTenths = temperature_in_tenths;
        }
        self.sumInTenths += temperature_in_tenths;
        self.count += 1;
    };

    // Formats "Hamburg=-23.0/18.0/59.2", which is minimum/mean/maximum.
    item format(self: StationStatistics): string = self.name
        + "="
        + formatTenths(self.minimumInTenths)
        + "/"
        + formatTenths(divideRoundingHalfUp(self.sumInTenths, self.count))
        + "/"
        + formatTenths(self.maximumInTenths);
};
