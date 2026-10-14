---
author: mario-nowak
status: draft
---

# Contracts proposal

## Basic case

### Syntax

```matcha
item Serializable = contract {
    item serialize(self: Satisfier): string;
};

item Point = structure satisfies Serializable {
    x: int;
    y: int;
    
    // must implement the contracts method
    item serialize(self) = "Point(x: " + self.x.toString() + ", y: " + self.y.toString() + ")";
};
```

## Generics interoperability

### Syntax

```matcha
item Serializable = contract {
    item serialize(self: Satisfier): string;
};

item Collapsable<Type> = contract {
    item collapse(self: Satisfier): Type;
};

item Point = structure satisfies Serializable, Collapsable {
    x: int;
    y: int;
    
    item serialize(self) = "Point(x: " + self.x.toString() + ", y: " + self.y.toString() + ")";

    item collapse(self) = self.x + self.y;
};
```

## Contract existential

### Syntax

```matcha
item Serializable = contract {
    item serialize(self: Satisfier): string;
};

item Point = structure satisfies Serializable {...};
item Line = structure satisfies Serializable {...};

val list: Serializable[] = [
    Point { ... },
    Line { ... },
];
```

## AI Generated

### Decisions

1. Conformance is explicit. A structure lists the contracts it satisfies: `structure satisfies Serializable, Collapsable`. A type never satisfies a contract by accident, only because its methods happen to match.
2. The compiler checks that the structure implements every method signature of each contract it satisfies.
3. `Satisfier` names the type that satisfies the contract. Inside a contract, `self: Satisfier` means "the type that implements this method".

### Rejected: retroactive conformance

Swift (`extension Money: JsonEncodable { ... }`) and Rust (`impl JsonEncodable for Money { ... }`) let code outside a type declare that the type satisfies a contract. This solves a real problem: you cannot add `satisfies` to a type from another library.

Matcha does not allow this. A type would get methods from somewhere outside its declaration, and a reader could not know what a type can do without searching the whole codebase. Everything a type can do stays in its own declaration. For types from other libraries, see the structure composition proposal.
