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
        user_uuid: string;
    },
};

item UserPayload = structure {
    name: string;
    email: string?; // <- conceptual syntax
};

item User = structure { ... };

item UserService = structure {
    item createUser(self: UserService, payload: UserPayload): User!UserServiceError {
        ...
    }
};

item UserController = structure {
    user_service: UserService;
    
    item putUser(self: UserController, blob: string): unit = {
        val payload = ...;
        user_service.createUser(payload) catch (user_service_error) match user_service_error {
            .MissingEmail(missing_email_error) => {
                
            };
        };
    };
};
```

### Draft 2

```matcha
item UserServiceError = error {
    MissingEmail: structure {
        user_uuid: string;
    },
    MissingBirthDate: structure {
        user_uuid: string;
    };

    item asJsonApiError(self: UserServiceError): JsonApiError = .{
        message = match self {
            .MissingEmail(payload) => "Missing email for user: " + payload.user_uuid,
            .MissingBirthDate(payload) => "Missing birth date for user: " + payload.user_uuid,
        };
    };
};

item UserPayload = structure {
    name: string;
    email: string?; // <- conceptual syntax
};

item User = structure { ... };

item UserService = structure {
    item createUser(self: UserService, payload: UserPayload): User!UserServiceError {
        ...
    }
};

item UserController = structure {
    user_service: UserService;
    
    item putUser(self: UserController, blob: string): unit = {
        val payload = ...;
        
        val user = user_service.createUser(payload) catch (user_service_error) {
            self.request.setContent(user_service_error.asJsonApiError().withStatus(.Code(400)));
            return;
        };

        // do something else with the user
    };
};
```
