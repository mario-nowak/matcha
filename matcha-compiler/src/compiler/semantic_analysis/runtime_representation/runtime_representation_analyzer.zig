const std = @import("std");
const typing = @import("typing");
const type_checking = @import("../type_checking/module.zig");
const runtime_representation_types = @import("runtime_representation_types.zig");

const RuntimeRepresentation = runtime_representation_types.RuntimeRepresentation;
const RuntimeRepresentationByNodeId = runtime_representation_types.RuntimeRepresentationByNodeId;
const RuntimeRepresentationByTypeId = runtime_representation_types.RuntimeRepresentationByTypeId;

const RuntimeRepresentationAnalysisState = union(enum) {
    Resolving,
    Resolved: RuntimeRepresentation,
};

const RuntimeRepresentationAnalysisStateByTypeId = std.AutoHashMap(typing.TypeId, RuntimeRepresentationAnalysisState);

pub const RuntimeRepresentationAnalyzer = struct {
    allocator: std.mem.Allocator,
    runtime_representation_by_node_id: RuntimeRepresentationByNodeId,
    runtime_representation_by_type_id: RuntimeRepresentationByTypeId,
    analysis_state_by_type_id: RuntimeRepresentationAnalysisStateByTypeId,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(allocator),
            .runtime_representation_by_type_id = RuntimeRepresentationByTypeId.init(allocator),
            .analysis_state_by_type_id = RuntimeRepresentationAnalysisStateByTypeId.init(allocator),
        };
    }

    pub fn analyzeRuntimeRepresentations(
        self: *@This(),
        type_check_result: *const type_checking.TypeCheckResult,
    ) anyerror!runtime_representation_types.RuntimeRepresentationResult {
        self.runtime_representation_by_node_id = RuntimeRepresentationByNodeId.init(self.allocator);
        self.runtime_representation_by_type_id = RuntimeRepresentationByTypeId.init(self.allocator);
        self.analysis_state_by_type_id = RuntimeRepresentationAnalysisStateByTypeId.init(self.allocator);

        // First we need to seed the runtime representation of every type that we encountered during the type analysis.
        try self.seedRuntimeRepresentationByTypeId(&type_check_result.type_store);

        var type_id_by_node_id_iterator = type_check_result.type_id_by_node_id.iterator();
        while (type_id_by_node_id_iterator.next()) |entry| {
            const runtime_representation = self.runtime_representation_by_type_id.get(entry.value_ptr.*) orelse unreachable;
            try self.runtime_representation_by_node_id.put(entry.key_ptr.*, runtime_representation);
        }

        return .{
            .runtime_representation_by_node_id = self.runtime_representation_by_node_id,
            .runtime_representation_by_type_id = self.runtime_representation_by_type_id,
        };
    }

    fn seedRuntimeRepresentationByTypeId(
        self: *@This(),
        type_store: *const typing.TypeStore,
    ) anyerror!void {
        for (0..type_store.count()) |index| {
            const type_id: typing.TypeId = @intCast(index);
            _ = try self.resolveRuntimeRepresentationOfType(type_store, type_id);
        }
    }

    fn resolveRuntimeRepresentationOfType(
        self: *@This(),
        type_store: *const typing.TypeStore,
        type_id: typing.TypeId,
    ) anyerror!RuntimeRepresentation {
        if (self.analysis_state_by_type_id.get(type_id)) |analysis_state| {
            // If we re-encounter a type that we already encountered during our recursive decent, we assume that the
            // type is self-recursive and therefore must have a runtime representation.
            // Example: `item Foo = Structure { bar: unit, baz: Foo };` requires a runtime representation, despite it
            // not being able to hold any real values.
            // This is more of a theoretical right now because `Foo` could be defined but not constructed in the current
            // version of matcha.
            return switch (analysis_state) {
                .Resolving => .Present,
                .Resolved => |runtime_representation| runtime_representation,
            };
        }

        // If we have not encountered the type yet, we set it as resolving before doing a potential recursive decent.
        try self.analysis_state_by_type_id.put(type_id, .Resolving);

        const runtime_representation = switch (type_store.getType(type_id)) {
            .Unit => .None,
            .Boolean,
            .Integer,
            .String,
            .Function,
            .UnionConstructor,
            .Union,
            => .Present,
            .Structure => |structure_type| try self.resolveRuntimeRepresentationOfStructureType(type_store, structure_type),
            .Array => |element_type_id| block: {
                _ = try self.resolveRuntimeRepresentationOfType(type_store, element_type_id);
                break :block .Present;
            },
        };

        try self.analysis_state_by_type_id.put(type_id, .{ .Resolved = runtime_representation });
        try self.runtime_representation_by_type_id.put(type_id, runtime_representation);

        return runtime_representation;
    }

    fn resolveRuntimeRepresentationOfStructureType(
        self: *@This(),
        type_store: *const typing.TypeStore,
        structure_type: typing.StructureType,
    ) anyerror!RuntimeRepresentation {
        for (structure_type.fields) |field| {
            _ = try self.resolveRuntimeRepresentationOfType(type_store, field.type_id);
        }

        return .Present;
    }
};
