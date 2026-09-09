# Equality Concept Document

This document is a scratchpad for `==` and `!=` syntax and user-visible semantics.

## Direction

The `==` operator compares two values of the same type and produces a `boolean`.

The `!=` operator is the logical negation of `==`.

```matcha
val equal = left == right;
val notEqual = left != right;
```

Operands with different types cannot be compared.

## Existing value equality

Booleans and integers use value equality.

```matcha
val booleansEqual = true == true; // true
val integersEqual = 42 == 42; // true
val integersDiffer = 42 == 7; // false
```

Strings use content equality even though their runtime representation contains a reference to heap storage.

```matcha
val left = "matcha";
val right = "mat" + "cha";
val equal = left == right; // true
```

String equality remains a deliberate exception to reference identity.

## Unit equality

The `unit` type has exactly one value. Two `unit` values therefore always compare equal.

```matcha
item doLeft(): unit = {};
item doRight(): unit = {};

val equal = doLeft() == doRight(); // true
val notEqual = doLeft() != doRight(); // false
```

Both operand expressions must still be evaluated even though the comparison result is known from their type.

A `unit` comparison does not require either operand to have a runtime register.

## Structure equality

Structures use reference identity.

```matcha
item Point = structure {
    x: int;
    y: int;
};

val first = Point { x = 1, y = 2 };
val alias = first;
val separate = Point { x = 1, y = 2 };
val aliasesEqual = first == alias; // true
val separateEqual = first == separate; // false
```

Two structures with equal fields are not equal unless both values refer to the same structure instance.

Structure equality is constant-time and does not recursively compare fields.

Different structure types cannot be compared, even when their fields are identical.

### Structures without runtime fields

Structures without runtime fields still have reference identity.

```matcha
item Token = structure {};

val first = Token {};
val alias = first;
val separate = Token {};
val aliasesEqual = first == alias; // true
val separateEqual = first == separate; // false
```

The runtime must preserve a distinct identity for each live structure instance. Exact allocation and layout rules belong in the implementation plan.

## Array equality

Arrays use reference identity.

```matcha
val first = [1, 2, 3];
val alias = first;
val separate = [1, 2, 3];
val aliasesEqual = first == alias; // true
val separateEqual = first == separate; // false
```

Array equality does not compare lengths or elements.

Arrays with different element types cannot be compared.

## Function equality

Functions do not support `==` or `!=`.

```matcha
item first(value: int): int = value;
item second(value: int): int = value;

val equal = first == second; // Error: functions do not support equality
```

Function equality would require closure and callable identity semantics that are not part of this proposal.

## Tagged-union equality

Tagged unions derive equality from their tags and payload types.

Detailed tagged-union equality semantics are defined in [the tagged-union proposal](../tagged-unions/proposal.md#equality).

Equality for `unit` and reference-like payload types is a prerequisite for tagged-union equality.

## Syntax selected for this draft

The existing `==` and `!=` operators are used for both value equality and reference identity.

The operand type determines the equality semantics.

No separate identity operator is introduced.

## Alternatives not selected

### Deep structure equality

Deep structure equality would recursively compare every field.

Not selected. It would make comparison cost depend on object size, require cycle handling, and interact poorly with mutable object graphs.

### Element-wise array equality

Element-wise array equality would compare array lengths and corresponding elements.

Not selected. Arrays are shared reference-like values, so identity equality matches their object model.

### Separate identity operator

A separate operator such as `===` could distinguish identity equality from value equality.

Not selected. Each Matcha type has one ordinary equality meaning, so a second equality operator is unnecessary.

### Singleton equality for structures without runtime fields

All instances of a structure without runtime fields could collapse into one value.

Not selected. Structures retain object identity regardless of their stored fields.

### Function identity equality

Functions could compare their runtime callable representations.

Not selected. Callable and closure identity semantics remain undefined.

## Outside this document

This document does not define:

- user-defined equality implementations
- operator overloading
- deep-equality library functions
- object headers
- garbage-collector allocation details
- tagged-union layout or discriminant representation
