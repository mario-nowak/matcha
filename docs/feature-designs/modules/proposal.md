# Module proposal

## V1 Scope

```mt
// -- module_a.mt
// Items can be prefixed the `export` modifier.
export item Point = structure {
    x: int;
    y: int;
};

// -- module_b.mt
// Conceptually, importing a file creates a `module`
// In V1, modules **must** be destructured to access its exported items
item { Point } = import "module_a.mt";
```

### Current Architecture

- `generateLlvmIrFromFile`
    - read file contents
    - lex file
    - parse file
    - Sema
        - name_resolution
        - type_analysis
        - control_flow_validation
        - runtime_representation
    - Code Generation

### Proposed architecture

#### Draft 1

- `generateLlvmIrFromFile`
    - `buildModuleGraph(input_path: []const u8): ModuleGraph`
        - `buildModuleNode(file_path: []const u8)`
            > I could build `module_node_by_node_id` during the recursive descend
            > I probably also need a `module_id_by_file_path`
            - if `module_id_by_file_id`.`get(file_path) != null`
            - parse/lex file ??using shared parser state??
            - foreach `import_path`
                - `buildModuleNode(import_path)`
            - build edges for other nodes
            - return node
    - depth first search through module graph
        - for each node
            - perform sema sub-pipeline
                - > Global `analyzed_program_module.AnalyzedProgram` or one per module node?

- `ModuleGraph`
    - > Directed (acyclic???) graph of all involved modules
    - > Could prohibit non-root modules from containing top level non-items
    - `root_module_id`: `Module`
    - `module_node_by_node_id`: ???
    - `module_node_by_file_path`

- `ModuleNode`
    - `id`: `ModuleId`
    - `file_path`: `[]const u8`
    - `module_edge_by_import_node_id`: `std.AutoHashMap(NodeId, ModuleEdge)`

- `ModuleEdge`
    - `module_id`: `ModuleId`

- `ModuleId`
    - > Can I use this value object as a hash key?

##### Open questions

- Do I need globally unique node ids?
    - Or can I use a composite module / ast node id?
- Do I want to allow cyclic imports?
    - If so, what happens to non-item statements?

#### Draft 2

- `generateLlvmIrFromFile`
    - with shared lex/parse state
    - `buildModuleFromFile(file_path: []const u8): Module`
        - ast = lex/parse file (each node in the package gets a unique ID)
        - find import statements
        - recursive `buildModuleFromFile` for each
            - need to check if module already exists for file
    - `analyzePackage`
        - package global type store and symbol table and runtime representation and exit behavior
        - for each module of package:
            - control flow validation
            - name resolution
                - first do package global hoisting of items and entire preliminary symbol and final symbol concept
            - type analysis
                - same concept as name resolution
            - runtime representation analysis
        - Core idea throughout:
        ```
        for (program.statements) |*statement| {
            try self.validateNode(statement, &context);
        }
        ```
        becomes
        ```
        for (package.module) |*module| {
            for (module.statements) |*statement| {
                try self.validateNode(statement, &context);
            }
        }
        ```
        - will most likely result in something like
            - `ResolvedPackage`
            - `AnalyzedPackage`
            - `LoweredPackage`
            - etc.
    - `lowerPackage`
        - same idea as analysis


- `Package`
    - `module_by_id`

- `Module`
    - `id`: `ModuleId`
    - `file_path`: `[]const u8`