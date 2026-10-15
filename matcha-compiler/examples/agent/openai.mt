// Sends the conversation to the OpenAI Chat Completions API and reads the reply.

item { startProcess } = import "builtin";

item { Json, JsonParser } = import "json.mt";
item { ToolCall, findMember, readText } = import "conversation.mt";
item { createToolDefinitions } = import "tools.mt";

export item ToolCallReply = structure {
    assistantMessage: Json;
    toolCalls: ToolCall[];
};

export item Reply = union {
    Text: string,
    ToolCalls: ToolCallReply,
    Error: string,
};

export item requestReply(messages: Json[]): Reply = {
    val body: Json = .Object([
        .{ key = "model", value = .Text("gpt-4.1-mini") },
        .{ key = "messages", value = .List(messages) },
        .{ key = "tools", value = .List(createToolDefinitions()) },
    ]);

    // curl reads the API key from the environment, so the key never appears in the code or in the arguments.
    // `startProcess` panics when curl fails, so one failed request ends the session.
    val response = startProcess("curl", [
        "--silent",
        "--show-error",
        "--fail-with-body",
        "--header",
        "Content-Type: application/json",
        "--variable",
        "%OPENAI_API_KEY",
        "--expand-header",
        "Authorization: Bearer {{OPENAI_API_KEY}}",
        "--data",
        body.serialize(),
        "https://api.openai.com/v1/chat/completions",
    ]);

    val json = match JsonParser.parse(response) {
        .Ok(value) => value,
        .Error(message) => {
            return .Error("invalid JSON from the API: " + message);
        },
    };

    return parseReply(json);
};

// Reads `choices[0].message`, which holds either text or tool calls.
item parseReply(json: Json): Reply = {
    val choices = match findMember(json, "choices") {
        .List(choices) => choices,
        else => {
            return .Error("the response has no choices");
        },
    };
    if choices.length == 0 {
        return .Error("the response has no choices");
    }
    val message = findMember(choices[0], "message");

    return match findMember(message, "tool_calls") {
        .List(calls) => .ToolCalls(.{
            assistantMessage = message,
            toolCalls = parseToolCalls(calls),
        }),
        else => match findMember(message, "content") {
            .Text(text) => .Text(text),
            else => .Error("the message has neither content nor tool calls"),
        },
    };
};

item parseToolCalls(calls: Json[]): ToolCall[] = {
    val tool_calls: ToolCall[] = [];
    for call in calls {
        val function = findMember(call, "function");
        tool_calls.append(.{
            id = readText(findMember(call, "id")),
            name = readText(findMember(function, "name")),
            arguments = readText(findMember(function, "arguments")),
        });
    }

    return tool_calls;
};
