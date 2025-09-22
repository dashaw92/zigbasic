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
    const val1str = try val1.toString(&self.alloc);
    const val2str = try val2.toString(&self.alloc);

    const output = try std.fmt.allocPrint(self.alloc, "{s}{s}", .{
        val1str,
        val2str,
    });

    if (val1 == .number) {
        self.alloc.free(val1str);
    }

    if (val2 == .number) {
        self.alloc.free(val2str);
    }

    try self.strings.append(self.alloc, output);
    return output;
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

    pub fn toString(self: *const Value, alloc: *Alloc) ![]const u8 {
        return switch (self.*) {
            .number => |num| std.fmt.allocPrint(alloc.*, "{}", .{num}),
            .string => |s| s,
        };
    }
};
