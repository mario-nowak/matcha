// A polynomial rolling hash over the bytes, with the base 31 like Java's `String.hashCode`. The modulo after every step
// keeps the value far below the int range.
export item hashPolynomial(text: string): int = {
    val BASE = 31;
    val MODULUS = 1000003;

    var hash = 0;
    var index = 0;
    while index < text.length : index += 1 {
        hash = (hash * BASE + text.getByteAt(index)) % MODULUS;
    }

    return hash;
};
