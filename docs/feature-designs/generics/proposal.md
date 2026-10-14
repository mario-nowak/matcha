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
val watcher = Watcher { subject = Point { x = 1, y = 2 } };
val x = watcher.subject.x;

// unions
item Optional<Type> = union {
    Some: Type,
    None,
};

// functions
item computeWatcher<Type>(subject: Type): Optional<Watcher<Type>> = .Some(.{ subject = subject });
```

## Semantics

## AI Generated

### Semantics

1. Generic items are monomorphized. The compiler emits one copy of a generic function or type for each set of type arguments that the program uses. There is no runtime cost and no runtime type information.
2. Type arguments appear only in type positions, for example after `:` or in an item declaration. There is no call syntax like `computeWatcher<Point>(...)`. This avoids the ambiguity between `<` as a comparison and `<` as the start of type arguments.
3. The compiler infers type arguments from the call arguments and from the expected type. When inference cannot decide, you annotate the binding:

   ```matcha
   val watcher = computeWatcher(Point { x = 1, y = 2 }); // Type is Point, from the argument
   val empty: Optional<Watcher<Point>> = .None; // Type comes from the binding
   ```

4. Static functions of a generic type use the implicit member form, with the type from the binding:

   ```matcha
   var counts: Map<string, int> = .empty();
   ```

### Order

Generics come after value semantics. With reference semantics, every structure is a pointer, so one compiled copy could serve all types (erasure). With value semantics, values have different sizes, so generics need monomorphization. Generics built before value semantics would likely use erasure and need a rebuild.
