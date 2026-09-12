---
author: @mario-nowak
---

# Structure Equality Operator Implementation Plan

## Core idea

- Structure which essentially don't have any fields that have any runtime representation should still allocate a single byte
- The comparison of two structures should compare these addresses
- Therefore, even structures without any fields with runtime representation still have "runtime representation"
    - Just a very small one

## Mental model building

1. Change runtime representation of structures without fields
    - Remove Array Runtime Representation element_type_id
        - It kind of seems useless after all
    - Let structures always have runtime representation
        - But I need some type of marker to decide if they are "empty" or not
        - I already have `StructureLayoutKind`!
        - That already does all of the heavy lifting
    - We have three concepts that need to align in a sensible way
        - During semantic analysis
            - `RuntimeRepresentation` union(enum)
                - cases
                    - `Array` <- this is what I plan to remove anyway
                        - QUESTION: Is it sane to remove this?
                            - I think the idea behind this type was to signalize that arrays always have a runtime representation
                            - Even if weird due to storing types without a runtime representation
                            - In which case they simply become a header that only stores the length
                                - QUESTION: Where is this decided currently?
                                    - ANSWER: during `emitArrayAppendCall`
                                        - Based on the runtime `RuntimeRepresentation` of the element type
                                            - NOTE: One more reason why structures should always have `RuntimeRepresentation.Present`
                                - NOTE: Structures without fields need to produce a "real" array to support true equality comparison
                                - NOTE: This points towards to fact that structures without layout should have a `Present` runtime representation
                                - NOTE: This would mean that basically only `unit` can have no runtime representation
                            - ANSWER: I think so, I cannot think of any reason to keep it
                    - `Present`
                    - `None`
                - QUESTION: Do I need a dedicated case for structures type? Or does `None` and `Present` imply different meanings for structures specifically?
                    - Right now structures have `Present` if they have any `Present` field
                        - And `Absent` otherwise
                        - Absent should mean "no runtime representation"
                        - But that would honestly, strictly speaking only apply to 
        - During lowering
            - `StructureLayoutKind` union(enum)
                - cases
                    - `Absent`
                        - Meant to represent structures without any actual layout
                        - NOTE: this still fits the concept of structures without any fields (with runtime representation)
                        - Right now all structure with `RuntimeRepresentation.Absent` receive this layout kind.
                    - `Present`: `StructureLayout` struct
                        - fields:
                            - `field_index_kind_by_definition_index`: `StructureLayoutFieldIndexKind` union(enum)
                                - cases
                                    - `Absent`
                                    - `Index`: u32
                - QUESTION: What are the exact semantics of `Absent` and `Present`
                    - Because `Present` might have `StructureLayoutFieldIndexKind.Absent` for all its fields
                    - Which would essentially be the same as `Absent`
                    - ANSWER: I think it would make sense to add validation to `StructureLayout` that prevents that
        - During emission
            - `EmissionResult`: union(enum)
                - cases
                    - `register`: `Register`
                    - `zero_sized`
                        - Right now structures with `RuntimeRepresentation.Absent` receive this result type
                        - NOTE: This means that structures without fields should not have this representation type
                    - `statement`
2. Allow structures without fields
    - This should be a simple step inside semantic analysis
    - The resulting `StructureLayoutKind` should simply be `.Absent`
3. Allocate a single byte for structures with `StructureLayoutKind.Absent`
4. Implement equality operator
    - Compare addresses

## Decisions

- `RuntimeRepresentation` of structures is always `Present`
    - Because it always has a runtime representation
- `StructureLayoutKind.Absent` should mean:
    - This structure does not exist at runtime in that layout, but instances of it do occupy memory and exist at runtime
- `StructureLayoutKind.Present` should mean:
    - This structure type exist as an llvm ir type and has at least one "real" field
- `EmissionResult.zero_sized` should mean:
    - This expression returns an expression that occupies no memory
    - So structures should always have it