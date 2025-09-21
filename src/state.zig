const std = @import("std");
const Alloc = std.mem.Allocator;
const Map = std.StringHashMap;

const State = @This();

symbols: Map(Value),
strings: std.ArrayList([]u8),
alloc: Alloc,

pub fn init(alloc: *const Alloc) !State {
    return .{
        .symbols = Map(Value).init(alloc.*),
        .strings = try std.ArrayList([]u8).initCapacity(alloc.*, 512),
        .alloc = alloc.*,
    };
}

pub fn deinit(self: *State) void {
    for (self.strings.items) |str| {
        self.alloc.free(str);
    }
    self.strings.deinit(self.alloc);
    self.symbols.deinit();
}

pub fn concat(self: *State, val1: Value, val2: Value) ![]const u8 {
    _ = self;
    _ = val1;
    _ = val2;
    return "todo";
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
