// Fetches a todo from the JSONPlaceholder mock API with curl, parses the JSON response into a domain
// object, changes it, and sends it back. JSONPlaceholder echoes the update without storing it.
//
// Run with: matcha run examples/todo-api-round-trip.mt
// Needs `curl` and network access.

// # Round trip

// `startProcess` panics when curl exits with a non-zero status. `--fail-with-body` makes HTTP errors do that.
item main(): unit = {
    val TODO_API_URL = "https://jsonplaceholder.typicode.com/todos/1";

    val response = startProcess("curl", ["--silent", "--show-error", "--fail-with-body", TODO_API_URL]);
    val json = match JsonParser.parse(response) {
        .Error(message) => {
            printString("Invalid JSON: " + message);
            return;
        },
        .Ok(value) => value,
    };
    val todo = match Todo.fromJson(json) {
        .Error(message) => {
            printString("Invalid todo: " + message);
            return;
        },
        .Ok(value) => value,
    };
    printString("Fetched: " + todo.describe());

    todo.title += " (reviewed)";
    todo.completed = true;

    val payload = todo.serialize();
    printString("Sending: " + payload);

    val update_response = startProcess("curl", [
        "--silent",
        "--show-error",
        "--fail-with-body",
        "--request",
        "PUT",
        "--header",
        "Content-Type: application/json; charset=UTF-8",
        "--data",
        payload,
        TODO_API_URL,
    ]);
    val updated_json = match JsonParser.parse(update_response) {
        .Error(message) => {
            printString("Invalid JSON: " + message);
            return;
        },
        .Ok(value) => value,
    };
    val updated_todo = match Todo.fromJson(updated_json) {
        .Error(message) => {
            printString("Invalid todo: " + message);
            return;
        },
        .Ok(value) => value,
    };
    printString("Updated: " + updated_todo.describe());
};

main();


// # JSON

item JsonParser = structure {
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
                        // ponytail: `\uXXXX`, `\b` and `\f` are rejected, because Matcha cannot build a string from a
                        // character code yet. Supporting them needs a builtin like `fromCodePoint(int): string`.
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
item JsonResult = union {
    Ok: Json,
    Error: string,
};

// A JSON value. Numbers are ints only, because Matcha has no floating-point type yet.
item Json = union {
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

item Member = structure {
    key: string;
    value: Json;
};

item TextResult = union {
    Ok: string,
    Error: string,
};


// # Domain

item Todo = structure {
    id: int;
    userId: int;
    title: string;
    completed: boolean;

    item fromJson(json: Json): TodoResult = {
        val members = match json {
            .Object(members) => members,
            else => {
                return .Error("expected a todo object");
            },
        };
        val todo = Todo {
            id = 0,
            userId = 0,
            title = "",
            completed = false,
        };
        var found_fields = 0;

        for member in members {
            match member.key {
                "id" => {
                    todo.id = match member.value {
                        .Number(id) => id,
                        else => {
                            return .Error("field 'id' must be a number");
                        },
                    };
                    found_fields += 1;
                },
                "userId" => {
                    todo.userId = match member.value {
                        .Number(user_id) => user_id,
                        else => {
                            return .Error("field 'userId' must be a number");
                        },
                    };
                    found_fields += 1;
                },
                "title" => {
                    todo.title = match member.value {
                        .Text(title) => title,
                        else => {
                            return .Error("field 'title' must be a string");
                        },
                    };
                    found_fields += 1;
                },
                "completed" => {
                    todo.completed = match member.value {
                        .Boolean(completed) => completed,
                        else => {
                            return .Error("field 'completed' must be a boolean");
                        },
                    };
                    found_fields += 1;
                },
                else => unit,
            };
        }

        if found_fields != 4 {
            return .Error("todo is missing fields");
        }

        return .Ok(todo);
    };

    item toJson(self: Todo): Json = .Object([
        Member { key = "id", value = .Number(self.id) },
        Member { key = "userId", value = .Number(self.userId) },
        Member { key = "title", value = .Text(self.title) },
        Member { key = "completed", value = .Boolean(self.completed) },
    ]);

    item serialize(self: Todo): string = self.toJson().serialize();

    item describe(self: Todo): string = "Todo #" + self.id.toString() + " (user " + self.userId.toString() + "): \""
        + self.title + "\" " + match self.completed {
            true => "[done]",
            false => "[open]",
        };
};

item TodoResult = union {
    Ok: Todo,
    Error: string,
};
