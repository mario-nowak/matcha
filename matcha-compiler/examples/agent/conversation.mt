// Chat messages, tool calls, and helpers to read JSON responses.

item { Json } = import "json.mt";

export item ToolCall = structure {
    id: string;
    name: string;
    // A JSON object, encoded as a string inside the response.
    arguments: string;
};

export item createSystemMessage(content: string): Json = createMessage("system", content);

export item createUserMessage(content: string): Json = createMessage("user", content);

export item createToolResultMessage(tool_call_id: string, content: string): Json = .Object([
    .{ key = "role", value = .Text("tool") },
    .{ key = "tool_call_id", value = .Text(tool_call_id) },
    .{ key = "content", value = .Text(content) },
]);

item createMessage(role: string, content: string): Json = .Object([
    .{ key = "role", value = .Text(role) },
    .{ key = "content", value = .Text(content) },
]);

// Matcha has no optionals yet, so a missing member is `.Null`.
export item findMember(json: Json, key: string): Json = match json {
    .Object(members) => {
        for member in members {
            if member.key == key {
                return member.value;
            }
        }

        return .Null;
    },
    else => .Null,
};

export item readText(json: Json): string = match json {
    .Text(text) => text,
    else => "",
};
