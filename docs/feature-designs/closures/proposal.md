---
author: claude
status: draft
---

# Closures proposal

## AI Generated

### Syntax

```matcha
val active = users.filter((user) => user.isActive);

val isAdult = (user: User) => user.age >= 18;

items.forEach((&item) => {
    item.count += 1;
});
```

1. A closure is `(parameters) => expression`, or `(parameters) => { ... }` with a block body. `=>` is the arrow that `match` already uses.
2. A closure bound to a name declares its parameter types, like a function: `(user: User) => ...`. The binding gets its type from the closure.
3. A closure passed as an argument can omit its parameter types, because the parameter it is passed to already declares them: `users.filter((user) => user.isActive)`.
4. A function type is written `(User) => boolean`, for example in the parameter list of `filter`.
5. A closure parameter can have the `&` marker, like a function parameter.

### Captures

1. A closure captures copies of the values it uses, when it is created. Inside the closure, captured values are read-only.
2. A closure cannot change a captured `var` that holds a value, and it cannot reassign a captured binding:

   ```matcha
   var total = 0;
   items.forEach((item) => total += item.price);
   // error: closures capture copies and cannot change `total`. Use a `for` loop.
   ```

3. A captured identity object is shared, because the capture copies the reference. The closure can change the object through its `var` fields. The sharing is visible in the type, as everywhere else.
4. Capturing an `&` parameter copies its current value, not the reference. So a reference never escapes its call.

### Closures are values

1. Copying a closure copies its captures.
2. Closures cannot be compared with `==`.
3. Every closure may outlive the function that created it, because it holds only copies and identity references. There are no lifetime rules.

### Precedent

Java requires captured locals to be "effectively final", which is a similar rule. Rust's `move` closures also capture by value. Swift captures variables by reference and boxes them, which is hidden sharing.
