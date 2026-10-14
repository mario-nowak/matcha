---
author: mario-nowak
status: draft
---

# Contracts proposal

## Basic case

### Syntax

```matcah
item Serializable = contract {
    item serialize(self: Satisfier): string;
};

item Point = structure satisfies Serializable {
    x: int;
    y: int;
    
    // must implement the contracts method
    item serialize(self) = "Point(x: " + x.toString() + ", y: " + y.toString() + ");
};
```

## Generics interoperability

### Syntax

```
item Serializable = contract {
    item serialize(self: Satisfier): string;
};

item Collapsable<Type> = contract {
    item collapse(self: Collapsable): Type
};

item Point = structrue satisfies Serializable, Collapsable {
    x: int;
    y: int;
    
    item serialize(self) = "Point(x: " + x.toString() + ", y: " + y.toString() + ");

    item collapse(self) = self.x + self.y;
}
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
