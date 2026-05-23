const std = @import("std");
const symbols = @import("symbols");
const typing = @import("typing");
const function_emission = @import("function_emission");

const Label = function_emission.Label;
const Storage = function_emission.Storage;

const StorageBySymbolId = std.AutoHashMap(symbols.SymbolId, Storage);

pub const LoopContext = struct {
    continue_label: Label,
    leave_label: Label,
};

pub const Environment = struct {
    storage_by_symbol_id: StorageBySymbolId,
    loop_context: ?LoopContext,
    function_return_type_id: typing.TypeId,

    pub fn init(
        allocator: std.mem.Allocator,
        loop_context: ?LoopContext,
        function_return_type_id: typing.TypeId,
    ) @This() {
        return .{
            .storage_by_symbol_id = StorageBySymbolId.init(allocator),
            .loop_context = loop_context,
            .function_return_type_id = function_return_type_id,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.storage_by_symbol_id.deinit();
    }
};

pub const EmissionResult = struct {
    register: ?function_emission.Register,
    exit_label: ?Label,
};
