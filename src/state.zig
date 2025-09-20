const std = @import("std");
const Alloc = std.mem.Allocator;
const Map = std.StringHashMap;

const State = @This();

symbols: Map(Value),
alloc: Alloc,

pub fn init(alloc: *const Alloc) !State {
    return .{
        .symbols = Map(Value).init(alloc.*),
        .alloc = alloc.*,
    };
}

pub fn deinit(self: *State) void {
    self.symbols.deinit();
}

pub fn valueOf(self: *State, ident: []const u8) ?Value {
    return self.symbols.get(ident);
}

pub fn set(self: *State, ident: []const u8, value: Value) !void {
    try self.symbols.put(ident, value);
}

pub const Value = union(enum) {
    number: f64,
    string: []const u8,
};
