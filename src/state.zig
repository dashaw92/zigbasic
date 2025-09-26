const std = @import("std");
const Alloc = std.mem.Allocator;
const Map = std.StringHashMap;

const State = @This();

//Redirects flow to a line number if set
jumpBack: ?usize,
//Variables
symbols: Map(Value),
//Heap allocated strings where the `,` (concat) operator was used
strings: std.ArrayList([]u8),
//Current stack of loops in the program
jumps: std.ArrayList(LoopState),
//Flag for programs to immediately halt interpretation via END keyword.
halt: bool,
alloc: Alloc,

pub fn init(alloc: *const Alloc) !State {
    return .{
        .jumpBack = null,
        .symbols = Map(Value).init(alloc.*),
        .strings = try std.ArrayList([]u8).initCapacity(alloc.*, 512),
        .jumps = try std.ArrayList(LoopState).initCapacity(alloc.*, 1024),
        .halt = false,
        .alloc = alloc.*,
    };
}

pub fn deinit(self: *State) void {
    for (self.strings.items) |str| {
        self.alloc.free(str);
    }
    self.jumps.deinit(self.alloc);
    self.strings.deinit(self.alloc);
    self.symbols.deinit();
}

pub fn pushJump(self: *State, loop: LoopState) !void {
    try self.jumps.append(self.alloc, loop);
}

pub fn peekJump(self: *State) ?LoopState {
    return self.jumps.getLastOrNull();
}

pub fn popJump(self: *State) ?LoopState {
    return self.jumps.pop();
}

pub fn setHalted(self: *State) void {
    self.halt = true;
}

pub fn isHalted(self: *State) bool {
    return self.halt;
}

pub fn clearLoops(self: *State) void {
    while (self.popJump()) |_| {}
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

pub fn drop(self: *State, ident: []const u8) void {
    _ = self.symbols.remove(ident);
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

pub const LoopState = struct {
    targetLine: usize,
    ident: []const u8,
    step: f64,
    start: f64,
    stop: f64,
};
