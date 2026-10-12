// Fetches a todo from the JSONPlaceholder mock API with curl, parses the JSON response into a domain
// object, changes it, and sends it back. JSONPlaceholder echoes the update without storing it.
//
// Run with: matcha run examples/todo-api-round-trip/main.mt
// Needs `curl` and network access.

item { startProcess, printString } = import "builtin";

// # Round trip

item { JsonParser } = import "json.mt";
item { Todo } = import "todo.mt";

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
