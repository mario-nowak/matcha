// A todo of the JSONPlaceholder API, and its conversion from and to JSON.

item { Json, Member } = import "json.mt";

export item Todo = structure {
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

export item TodoResult = union {
    Ok: Todo,
    Error: string,
};
