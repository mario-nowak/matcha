// The tools the model can call, and their execution.

item { readFile } = import "builtin";

item { Json, JsonParser, Member } = import "json.mt";
item { ToolCall, createToolResultMessage, findMember, readText } = import "conversation.mt";

export item createToolDefinitions(): Json[] = [
    createToolDefinition("read_file", "Reads a file and returns its content.", ["path"]),
    createToolDefinition("write_file", "Replaces the content of a file.", ["path", "content"]),
];

// Every parameter is a required string, which is all these tools need.
item createToolDefinition(name: string, description: string, parameter_names: string[]): Json = {
    val properties: Member[] = [];
    val required: Json[] = [];
    for parameter_name in parameter_names {
        properties.append(.{
            key = parameter_name,
            value = .Object([.{ key = "type", value = .Text("string") }]),
        });
        required.append(.Text(parameter_name));
    }

    return .Object([
        .{ key = "type", value = .Text("function") },
        .{ key = "function", value = .Object([
            .{ key = "name", value = .Text(name) },
            .{ key = "description", value = .Text(description) },
            .{ key = "parameters", value = .Object([
                .{ key = "type", value = .Text("object") },
                .{ key = "properties", value = .Object(properties) },
                .{ key = "required", value = .List(required) },
            ]) },
        ]) },
    ]);
};

// `readFile` panics for a missing file, so a wrong path from the model ends the session.
export item executeToolCall(tool_call: ToolCall): Json = {
    // The arguments arrive as a JSON string inside the JSON response, so they are parsed a second time.
    val arguments = match JsonParser.parse(tool_call.arguments) {
        .Ok(value) => value,
        .Error(message) => {
            return createToolResultMessage(tool_call.id, "Error: invalid arguments: " + message);
        },
    };
    val path = readText(findMember(arguments, "path"));

    val result = match tool_call.name {
        "read_file" => readFile(path),
        "write_file" => writeFileDummy(path, readText(findMember(arguments, "content"))),
        else => "Error: unknown tool " + tool_call.name,
    };

    return createToolResultMessage(tool_call.id, result);
};

// DUMMY: replace with the `writeFile` builtin once it exists. Until then, the model is told the truth.
item writeFileDummy(path: string, content: string): string =
    "Not written: writing files is not implemented yet. The content for " + path + " had " + content.length.toString() + " bytes.";
