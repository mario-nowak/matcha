// Temperatures are stored in tenths of a degree, so "-12.3" is -123. That avoids floating point numbers entirely.

// Parses "-12.3" or "4.5". 1BRC temperatures always have exactly one fractional digit.
export item parseTemperatureTenths(text: string): int = {
    val MINUS_BYTE = 45;
    val DOT_BYTE = 46;
    val ZERO_BYTE = 48;

    var sign = 1;
    var index = 0;
    if text.getByteAt(0) == MINUS_BYTE {
        sign = -1;
        index = 1;
    }

    var tenths_absolute = 0;
    while index < text.length : index += 1 {
        val byte = text.getByteAt(index);
        if byte != DOT_BYTE {
            tenths_absolute = tenths_absolute * 10 + byte - ZERO_BYTE;
        }
    }

    return sign * tenths_absolute;
};

export item formatTemperatureTenths(temperature_tenths: int): string = {
    val sign = if temperature_tenths < 0 { "-" } else { "" };
    val tenths_absolute = if temperature_tenths < 0 { -temperature_tenths } else { temperature_tenths };
    val degrees_whole = tenths_absolute / 10;
    val tenths_digit = tenths_absolute % 10;

    return sign + degrees_whole.toString() + "." + tenths_digit.toString();
};

// Rounds half up, toward positive infinity, like `Math.round` in the 1BRC reference implementation. So -0.05 becomes
// 0.0, not -0.1. The divisor must be positive.
export item divideRoundingHalfUp(dividend: int, divisor: int): int = divideRoundingDown(2 * dividend + divisor, 2 * divisor);

// `/` truncates toward zero, so a negative quotient with a remainder is one too large.
item divideRoundingDown(dividend: int, divisor: int): int = {
    val quotient = dividend / divisor;

    return if dividend % divisor < 0 { quotient - 1 } else { quotient };
};
