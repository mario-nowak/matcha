# One Billion Row Challenge in Matcha

A Matcha solution to the [One Billion Row Challenge](https://github.com/gunnarmorling/1brc) (1BRC). The program reads a file with one billion lines like `Hamburg;12.0` and prints the minimum, mean, and maximum temperature per station, sorted by name.

```bash
matcha run examples/one-billion-row-challenge/main.mt -- examples/one-billion-row-challenge/measurements.txt
```

## Result

On the full dataset, Matcha takes **102 seconds** and uses at most **16.4 MB** of memory.

| Language | Time | Compared to Matcha | Memory |
|---|---|---|---|
| Go 1.25.1 | 36.1 s | 2.8× faster | 5.3 MB |
| Rust 1.96.0 | 38.7 s | 2.6× faster | 3.0 MB |
| **Matcha** | **102.0 s** | – | **16.4 MB** |
| Java 25, official 1BRC baseline | 173.1 s | 1.7× slower | 416 MB |
| Node.js 24.8.0 | 204.6 s | 2.0× slower | 184 MB |
| Python 3.14.7 | 290.9 s | 2.9× slower | 15.4 MB |
| Swift 6.2.3 | 361.0 s | 3.5× slower | 6.1 MB |

## How it was measured

- Machine: MacBook Pro (`Mac15,7`) with an Apple M3 Pro and 36 GB of memory, macOS 27.0.1.
- Data: 1 billion lines (13.8 GB) with 413 stations, made by a generator that follows the official one. The file was in the operating system's file cache.
- Every program is single-threaded and uses the same simple approach: read line by line, parse the temperature, update a hash map, then sort and print. None uses threads, memory-mapped files, or SIMD.
- Java runs the unchanged [official baseline](https://github.com/gunnarmorling/1brc/blob/main/src/main/java/dev/morling/onebrc/CalculateAverage_baseline.java). The other programs are plain, idiomatic versions of the same approach.
- Each program ran once. All of them printed the exact expected result.
- Matcha program and compiler at commit `75a637d`. The compiler compiles programs with `-O2`.
