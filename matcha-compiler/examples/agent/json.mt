// Parses JSON text into `Json` values and serializes them back.

export item JsonParser = structure {
    input: string;
    position: int;

    item parse(input: string): JsonResult = {
        val parser = JsonParser {
            input = input,
            position = 0,
        };
        val json = match parser.parseValue() {
            .Error(message) => {
                return .Error(message);
            },
            .Ok(value) => value,
        };

        parser.skipWhitespace();
        if parser.position < input.length {
            return .Error(parser.error("unexpected trailing content"));
        }

        return .Ok(json);
    };

    item parseValue(self: JsonParser): JsonResult = {
        self.skipWhitespace();

        return match self.peek() {
            "{" => self.parseObject(),
            "[" => self.parseList(),
            "\"" => match self.parseText() {
                .Ok(text) => .Ok(.Text(text)),
                .Error(message) => .Error(message),
            },
            "t" => self.parseKeyword("true", .Boolean(true)),
            "f" => self.parseKeyword("false", .Boolean(false)),
            "n" => self.parseKeyword("null", .Null),
            "" => .Error(self.error("unexpected end of input")),
            else => self.parseNumber(),
        };
    };

    item parseKeyword(self: JsonParser, keyword: string, value: Json): JsonResult = {
        val end = self.position + keyword.length;
        if end > self.input.length {
            return .Error(self.error("expected " + keyword));
        }
        if self.input.slice(self.position, end) != keyword {
            return .Error(self.error("expected " + keyword));
        }
        self.position = end;

        return .Ok(value);
    };

    item parseNumber(self: JsonParser): JsonResult = {
        val start = self.position;
        if self.peek() == "-" {
            self.skip();
        }
        while JsonParser.isDigit(self.peek()) {
            self.skip();
        }

        val digits = self.input.slice(start, self.position);
        return match {
            digits == "" or digits == "-" => .Error(self.error("unexpected character '" + self.peek() + "'")),
            self.peek() == "." or self.peek() == "e" or self.peek() == "E" => .Error(self.error("only integer numbers are supported")),
            else => .Ok(.Number(digits.toInt())),
        };
    };

    item parseText(self: JsonParser): TextResult = {
        self.skip(); // The opening quote.
        var text = "";

        loop {
            val character = self.next();
            match character {
                "\"" => {
                    return .Ok(text);
                },
                "" => {
                    return .Error(self.error("unterminated string"));
                },
                "\\" => {
                    text += match self.next() {
                        "\"" => "\"",
                        "\\" => "\\",
                        "/" => "/",
                        "n" => "\n",
                        "r" => "\r",
                        "t" => "\t",
                        // DUMMY: replace with real UTF-8 decoding once a builtin like `fromCodePoint(int): string`
                        // exists. Until then, every `\uXXXX` becomes "?", so responses with non-ASCII text still parse.
                        "u" => {
                            self.skip();
                            self.skip();
                            self.skip();
                            self.skip();

                            "?"
                        },
                        // `\b` and `\f` are rejected, because Matcha cannot build a string from a character code yet.
                        else => {
                            return .Error(self.error("unsupported string escape"));
                        },
                    };
                },
                else => {
                    text += character;
                },
            };
        }
    };

    item parseList(self: JsonParser): JsonResult = {
        self.skip(); // The opening bracket.
        val values: Json[] = [];
        self.skipWhitespace();
        if self.peek() == "]" {
            self.skip();
            return .Ok(.List(values));
        }

        loop {
            val value = match self.parseValue() {
                .Error(message) => {
                    return .Error(message);
                },
                .Ok(value) => value,
            };
            values.append(value);

            self.skipWhitespace();
            match self.next() {
                "," => unit,
                "]" => {
                    return .Ok(.List(values));
                },
                else => {
                    return .Error(self.error("expected ',' or ']'"));
                },
            };
        }
    };

    item parseObject(self: JsonParser): JsonResult = {
        self.skip(); // The opening brace.
        val members: Member[] = [];
        self.skipWhitespace();
        if self.peek() == "}" {
            self.skip();
            return .Ok(.Object(members));
        }

        loop {
            self.skipWhitespace();
            if self.peek() != "\"" {
                return .Error(self.error("expected a string key"));
            }
            val key = match self.parseText() {
                .Error(message) => {
                    return .Error(message);
                },
                .Ok(text) => text,
            };

            self.skipWhitespace();
            if self.next() != ":" {
                return .Error(self.error("expected ':'"));
            }

            val value = match self.parseValue() {
                .Error(message) => {
                    return .Error(message);
                },
                .Ok(value) => value,
            };
            members.append(.{
                key = key,
                value = value,
            });

            self.skipWhitespace();
            match self.next() {
                "," => unit,
                "}" => {
                    return .Ok(.Object(members));
                },
                else => {
                    return .Error(self.error("expected ',' or '}'"));
                },
            };
        }
    };

    // Returns the next character, or "" at the end of the input.
    item peek(self: JsonParser): string = match {
        self.position < self.input.length => self.input.slice(self.position, self.position + 1),
        else => "",
    };

    item next(self: JsonParser): string = {
        val character = self.peek();
        self.skip();
        return character;
    };

    item skip(self: JsonParser): unit = {
        self.position += 1;
    };

    item skipWhitespace(self: JsonParser): unit = {
        while JsonParser.isWhitespace(self.peek()) {
            self.skip();
        }
    };

    item error(self: JsonParser, message: string): string = message + " at position " + self.position.toString();

    item isDigit(character: string): boolean = match character {
        "0" => true,
        "1" => true,
        "2" => true,
        "3" => true,
        "4" => true,
        "5" => true,
        "6" => true,
        "7" => true,
        "8" => true,
        "9" => true,
        else => false,
    };

    item isWhitespace(character: string): boolean = match character {
        " " => true,
        "\n" => true,
        "\r" => true,
        "\t" => true,
        else => false,
    };
};

// Matcha has no generics, so every result type is its own union.
export item JsonResult = union {
    Ok: Json,
    Error: string,
};

// A JSON value. Numbers are ints only, because Matcha has no floating-point type yet.
export item Json = union {
    Null,
    Boolean: boolean,
    Number: int,
    Text: string,
    List: Json[],
    Object: Member[],

    item serialize(self: Json): string = match self {
        .Null => "null",
        .Boolean(value) => match value {
            true => "true",
            false => "false",
        },
        .Number(value) => value.toString(),
        .Text(text) => Json.quote(text),
        .List(values) => {
            var output = "[";
            var index = 0;
            while index < values.length : index += 1 {
                if index > 0 {
                    output += ",";
                }
                output += values[index].serialize();
            }

            output + "]"
        },
        .Object(members) => {
            var output = "{";
            var index = 0;
            while index < members.length : index += 1 {
                if index > 0 {
                    output += ",";
                }
                output += Json.quote(members[index].key) + ":" + members[index].value.serialize();
            }

            output + "}"
        },
    };

    // Renders `text` as a JSON string literal.
    item quote(text: string): string = {
        var quoted = "\"";
        var index = 0;
        while index < text.length : index += 1 {
            val character = text.slice(index, index + 1);
            quoted += match character {
                "\"" => "\\\"",
                "\\" => "\\\\",
                "\n" => "\\n",
                "\r" => "\\r",
                "\t" => "\\t",
                else => character,
            };
        }

        return quoted + "\"";
    };
};

export item Member = structure {
    key: string;
    value: Json;
};

item TextResult = union {
    Ok: string,
    Error: string,
};
