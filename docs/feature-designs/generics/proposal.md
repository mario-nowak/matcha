---
author: mario-nowak
status: draft
---

# Generics proposal

## Syntax

```matcha
// structures
item Point = structure {
    x: int;
    y: int;
};
item Watcher<Type> = structure {
    subject: Type;
};
// implicitly typed as Watcher<Point>;
val watcher = Watcher { subject = Point };
val x = watcher.subject.x;

// unions
item Result<Type> = union {
    Some: Type,
    None,
};

// functions
item computeWatcher<Type>(): Result<Watcher<Type>> = .Some(.{ subject = .{ x = 3, y = 4 } });
```

## Semantics
