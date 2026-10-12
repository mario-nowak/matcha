const std = @import("std");

const TypeId = @import("type.zig").TypeId;
const TypeKind = @import("type.zig").TypeKind;
const Type = @import("type.zig").Type;
const PreliminaryType = @import("type.zig").PreliminaryType;

/// Table for storing types by their ID.
pub const TypeStore = struct {
    arena: std.mem.Allocator,
    preliminary_entries: std.AutoHashMap(TypeId, PreliminaryType),
    entries: std.AutoHashMap(TypeId, Type),
    next_type_id: TypeId,
    array_type_id_by_element_type_id: std.AutoHashMap(TypeId, TypeId),
    unit_type_id: TypeId,
    boolean_type_id: TypeId,
    integer_type_id: TypeId,
    string_type_id: TypeId,

    pub const Iterator = struct {
        inner: std.AutoHashMap(TypeId, Type).Iterator,

        pub const Entry = struct {
            type_id: TypeId,
            matcha_type: Type,
        };

        pub fn next(self: *@This()) ?Entry {
            const entry = self.inner.next() orelse return null;
            return .{ .type_id = entry.key_ptr.*, .matcha_type = entry.value_ptr.* };
        }
    };

    pub fn init(arena: std.mem.Allocator) !@This() {
        var store = @This(){
            .arena = arena,
            .preliminary_entries = std.AutoHashMap(TypeId, PreliminaryType).init(arena),
            .entries = std.AutoHashMap(TypeId, Type).init(arena),
            .next_type_id = 0,
            .array_type_id_by_element_type_id = std.AutoHashMap(TypeId, TypeId).init(arena),
            .unit_type_id = undefined,
            .boolean_type_id = undefined,
            .integer_type_id = undefined,
            .string_type_id = undefined,
        };

        store.unit_type_id = try store.addType(.unit);
        store.boolean_type_id = try store.addType(.boolean);
        store.integer_type_id = try store.addType(.integer);
        store.string_type_id = try store.addType(.string);

        return store;
    }

    pub fn addType(self: *@This(), matcha_type: Type) !TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        try self.entries.put(type_id, matcha_type);

        return type_id;
    }

    pub fn addPreliminaryType(self: *@This(), kind: TypeKind) !TypeId {
        const type_id = self.next_type_id;
        self.next_type_id += 1;
        try self.preliminary_entries.put(type_id, .{ .kind = kind });

        return type_id;
    }

    pub fn finalizeType(self: *@This(), type_id: TypeId, matcha_type: Type) !void {
        const removed_entry = self.preliminary_entries.fetchRemove(type_id) orelse {
            if (self.entries.contains(type_id)) {
                std.debug.panic("Internal Compiler Error: Type {d} is already finalized", .{type_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid type ID: {d}", .{type_id});
        };
        if (removed_entry.value.kind != std.meta.activeTag(matcha_type)) {
            std.debug.panic("Internal Compiler Error: Cannot change kind of type {d} during finalization", .{type_id});
        }
        try self.entries.put(type_id, matcha_type);
    }

    pub fn getType(self: *const @This(), type_id: TypeId) Type {
        return self.entries.get(type_id) orelse {
            if (self.preliminary_entries.contains(type_id)) {
                std.debug.panic("Internal Compiler Error: Type {d} is not finalized", .{type_id});
            }
            std.debug.panic("Internal Compiler Error: Invalid type ID: {d}", .{type_id});
        };
    }

    pub fn getArrayType(self: *const @This(), element_type_id: TypeId) ?TypeId {
        return self.array_type_id_by_element_type_id.get(element_type_id);
    }

    pub fn getOrCreateArrayType(self: *@This(), element_type_id: TypeId) !TypeId {
        if (self.array_type_id_by_element_type_id.get(element_type_id)) |existing_type_id| {
            return existing_type_id;
        }

        const type_id = try self.addType(.{ .array = element_type_id });
        try self.array_type_id_by_element_type_id.put(element_type_id, type_id);
        return type_id;
    }

    /// Number of allocated type IDs. IDs are dense, so all IDs are smaller than this count.
    pub fn count(self: *const @This()) u32 {
        return self.next_type_id;
    }

    pub fn assertAllFinalized(self: *const @This()) void {
        if (self.preliminary_entries.count() == 0) return;
        var preliminary_types = self.preliminary_entries.iterator();
        while (preliminary_types.next()) |entry| {
            std.debug.print("Type {d} ({s}) is not finalized\n", .{ entry.key_ptr.*, @tagName(entry.value_ptr.kind) });
        }

        std.debug.panic("Internal Compiler Error: {d} types are not finalized", .{self.preliminary_entries.count()});
    }

    pub fn iterator(self: *const @This()) Iterator {
        return .{ .inner = self.entries.iterator() };
    }
};
