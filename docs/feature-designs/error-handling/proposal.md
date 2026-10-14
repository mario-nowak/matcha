---
author: mario-nowak
status: draft
---

# Error handling proposal

## Syntax

### Draft 1

```matcha
item UserServiceError = error {
    MissingEmail: structure {
        userUuid: string;
    },
};

item UserPayload = structure {
    name: string;
    email: string?; // <- conceptual syntax
};

item User = structure { ... };

item UserService = structure {
    item createUser(self: UserService, payload: UserPayload): User!UserServiceError = {
        ...
    };
};

item UserController = structure {
    userService: UserService;
    
    item putUser(self: UserController, blob: string): unit = {
        val payload = ...;
        self.userService.createUser(payload) catch (userServiceError) match userServiceError {
            .MissingEmail(missingEmailError) => {
                
            },
        };
    };
};
```

### Draft 2

```matcha
item UserServiceError = error {
    MissingEmail: structure {
        userUuid: string;
    },
    MissingBirthDate: structure {
        userUuid: string;
    },

    item asJsonApiError(self: UserServiceError): JsonApiError = .{
        message = match self {
            .MissingEmail(payload) => "Missing email for user: " + payload.userUuid,
            .MissingBirthDate(payload) => "Missing birth date for user: " + payload.userUuid,
        },
    };
};

item UserPayload = structure {
    name: string;
    email: string?; // <- conceptual syntax
};

item User = structure { ... };

item UserService = structure {
    item createUser(self: UserService, payload: UserPayload): User!UserServiceError = {
        ...
    };
};

item UserController = structure {
    userService: UserService;
    
    item putUser(self: UserController, blob: string): unit = {
        val payload = ...;
        
        val user = self.userService.createUser(payload) catch (userServiceError) {
            self.request.setContent(userServiceError.asJsonApiError().withStatus(.Code(400)));
            return;
        };

        // do something else with the user
    };
};
```

## AI Generated

### Direction

Errors follow Zig: error sets, `try`, and `catch`. Unlike Zig, an error case can carry a payload, and an error set can have methods. Service code needs that context, for example which user failed validation or which HTTP status to return. A function that can fail declares its error set after `!`: `User!UserServiceError`.

### Three ways to handle an error

```matcha
val user = try createUser(payload); // propagate the error to the caller

val user = createUser(payload) catch (error) { // handle the error as one value
    ...
};

val user = createUser(payload) catch { // handle each case
    .MissingEmail(error) => return respond(400, error.asJsonApiError()),
    .MissingBirthDate(error) => return respond(400, error.asJsonApiError()),
};
```

1. `catch (name) { ... }` with a name handles the error as one value in a normal block.
2. `catch { ... }` without a name matches on the error. It reuses the `match` arm syntax, and the compiler checks that the arms are exhaustive.
3. `try x` is shorthand for `x catch (error) { return error; }`.

The parentheses tell the parser which form it reads. `catch match { ... }` was rejected, because `match { ... }` without a subject already means boolean conditions.

### Rules

1. A `catch` block or arm produces a value of the success type, or it leaves the function.
2. A call that can fail and has no `try` or `catch` is a compile error.

### Open questions

1. How error sets combine. A function that calls several services with different error sets needs a rule for its own signature. Zig merges sets (`A || B`) and can infer them (`!User`).
2. How `else` binds the error in the arm form, for example `else (error) => return error`.
3. Why `error` is a separate keyword instead of `union`. A possible reason: only error types may appear after `!`, and only error sets can combine.
