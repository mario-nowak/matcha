item { readFileChunk } = import "builtin";

// Reads a file line by line, one chunk at a time, instead of reading the whole file at once. A chunk usually ends
// inside a line, so the last element of `lines` is the incomplete line until the end of the file is reached.
export item LineReader = structure {
    path: string;
    offset_bytes: int;
    lines: string[];
    line_index: int;
    is_at_end_of_file: boolean;

    item open(path: string): LineReader = {
        val lines: string[] = [""];

        return .{
            path = path,
            offset_bytes = 0,
            lines = lines,
            line_index = 0,
            is_at_end_of_file = false,
        };
    };

    item hasNextLine(self: LineReader): boolean = {
        while self.line_index == self.lines.length - 1 and not self.is_at_end_of_file {
            self.readNextChunk();
        }
        if self.line_index < self.lines.length - 1 {
            return true;
        }

        // At the end of the file, the last line has no newline after it. It is empty when the file ends with a newline.
        return self.line_index == self.lines.length - 1 and self.lines[self.line_index].length > 0;
    };

    // Call only after `hasNextLine` returned true.
    item nextLine(self: LineReader): string = {
        val line = self.lines[self.line_index];
        self.line_index += 1;

        return line;
    };

    item readNextChunk(self: LineReader): unit = {
        val CHUNK_LENGTH_BYTES = 1048576;
        val chunk = readFileChunk(self.path, self.offset_bytes, CHUNK_LENGTH_BYTES);
        if chunk.length == 0 {
            self.is_at_end_of_file = true;
            return;
        }
        self.offset_bytes += chunk.length;

        val incomplete_line = self.lines[self.lines.length - 1];
        self.lines = (incomplete_line + chunk).split("\n");
        self.line_index = 0;
    };
};
