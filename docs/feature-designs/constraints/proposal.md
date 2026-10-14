---
author: claude
status: draft
---

# Constraints proposal

## AI Generated

A constraint limits which types a type parameter accepts. Constraints build on generics, contracts, and shapes.

### Two kinds of constraints

1. A contract constrains methods. The type argument must satisfy the contract.

   ```matcha
   item largest<T: Comparable>(items: T[]): T = { ... };
   ```

2. A shape constrains fields. The type argument must have at least these fields.

   ```matcha
   item greet<T: { name: string, .. }>(user: T): string = "Hello, " + user.name;
   ```

### Open shapes as anonymous constraints

An open shape in a parameter type is the anonymous form of a shape constraint. These two declarations mean the same:

```matcha
item greet<T: { name: string, .. }>(user: T): string = "Hello, " + user.name;
item greet(user: { name: string, .. }): string = "Hello, " + user.name;
```

The named form is necessary when the type parameter appears more than once, for example when the function returns the same type it gets.

### Semantics

Constrained generics are monomorphized like all generics. Calls to contract methods are direct calls. There is no runtime dispatch.

### Open questions

1. The syntax for several constraints on one type parameter, for example a contract and a shape together.
