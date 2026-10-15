// A minimal coding agent: you type a request, and the model answers or calls tools to read and change files.
// It talks to the OpenAI Chat Completions API through curl.
//
// Run with: OPENAI_API_KEY=... matcha run examples/agent/main.mt
// Needs curl 8.3 or newer, which reads the API key from the environment itself.

item { readLine, printString } = import "builtin";

item { Json } = import "json.mt";
item { createSystemMessage, createUserMessage } = import "conversation.mt";
item { requestReply } = import "openai.mt";
item { executeToolCall } = import "tools.mt";

item main(): unit = {
    val messages: Json[] = [createSystemMessage("You are a coding assistant. Use the tools to read and change files.")];

    loop {
        printString(">");
        val input = readLine();
        // `readLine` returns "" at the end of the input.
        if input == "" or input == "exit" {
            leave;
        }
        messages.append(createUserMessage(input));
        respond(messages);
    }
};

// Answers one user turn. The model may call tools several times before it answers with text. The bound keeps a
// confused model from calling tools forever.
item respond(messages: Json[]): unit = {
    val MAX_TOOL_ROUNDS = 10;
    var round = 0;
    while round < MAX_TOOL_ROUNDS : round += 1 {
        match requestReply(messages) {
            .Error(message) => {
                printString("Error: " + message);
                return;
            },
            .Text(text) => {
                printString(text);
                return;
            },
            .ToolCalls(reply) => {
                // The API needs the message with the tool calls before the tool results.
                messages.append(reply.assistantMessage);
                for tool_call in reply.toolCalls {
                    printString("[tool] " + tool_call.name);
                    messages.append(executeToolCall(tool_call));
                }
            },
        };
    }
    printString("Stopped after " + MAX_TOOL_ROUNDS.toString() + " tool rounds.");
};

main();
