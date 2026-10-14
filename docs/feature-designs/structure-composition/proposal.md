---
author: claude
status: draft
---

# Structure composition proposal

## AI Generated

### Motivation

Matcha rejects retroactive conformance (see the contracts proposal). So a type from another library cannot get new methods or new contracts. Structure composition declares a new type with the same data instead.

### Syntax

`..` inside a structure declaration takes all fields of another structure:

```matcha
item MyMoney = structure satisfies JsonEncodable {
    ..Money;

    item formatted(self: MyMoney): string = Money.formatted(Money { ..self });
    item toJson(self: MyMoney): string = ...;
};

item AuditedUser = structure {
    ..User;
    ..AuditInfo;
};
```

`..` then means "all fields of" at every level: in open shapes, in value spread, and in type declarations.

### Semantics

1. Only fields are taken, not methods. `MyMoney` is a new nominal type that has the same data as `Money`. Inherited methods would cause confusing types, for example `myMoney.add(other)` returning a `Money`.
2. Every reused behavior is an explicit method that delegates, as in `formatted` above.
3. Conversion is explicit, through value spread, in both directions: `MyMoney { ..price }` and `Money { ..myMoney }`.
4. Two composed structures with the same field name are a compile error.
5. Opaque and identity structures cannot be composed this way. An opaque structure may have private fields, and its invariant belongs to its constructor. An identity structure is about one shared object, and spread copies. For those types, a field that holds the original value is the way: `money: Money;`.

### Usage

A composed type is usually a boundary type, not a replacement. The rest of the code keeps using `Money`, and the conversion appears only where the contract is necessary:

```matcha
encode(MyMoney { ..price });
```

Then most composed types need no delegating methods at all.

### Alternative not decided: a type operator

```matcha
item AuditedUser = User & AuditInfo;
```

A type operator is compact and composes inline in type positions. It has no body, so it cannot add methods or `satisfies`. `&` is also already the parameter marker, and a combination operator invites an untagged `|` next to tagged unions.
