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
//1 KB of emulated memory.
memory: [1024]Value,
//Extensions registered prior to execution enabling peek/poke to be used for real IO.
extensions: std.ArrayList(MemoryExtension),
//array ID for deinit
arrays: std.ArrayList(Array),
alloc: *const Alloc,

pub fn init(alloc: *const Alloc) !State {
    return .{
        .jumpBack = null,
        .symbols = Map(Value).init(alloc.*),
        .strings = try std.ArrayList([]u8).initCapacity(alloc.*, 512),
        .jumps = try std.ArrayList(LoopState).initCapacity(alloc.*, 1024),
        .memory = [_]Value{Value{ .number = 0 }} ** (1024),
        .extensions = try std.ArrayList(MemoryExtension).initCapacity(alloc.*, 1024),
        .arrays = try std.ArrayList(Array).initCapacity(alloc.*, 16),
        .halt = false,
        .alloc = alloc,
    };
}

pub fn deinit(self: *State) void {
    for (self.strings.items) |str| {
        self.alloc.free(str);
    }
    self.jumps.deinit(self.alloc.*);
    self.strings.deinit(self.alloc.*);
    self.extensions.deinit(self.alloc.*);

    for (self.arrays.items) |arr| {
        self.alloc.free(arr.array);
    }
    self.arrays.deinit(self.alloc.*);
    self.symbols.deinit();
}

pub fn registerExtension(self: *State, extension: MemoryExtension) !void {
    for (self.extensions.items) |other| {
        if (other.address == extension.address) return error.AddressAlreadyInUse;
    }
    try self.extensions.append(self.alloc.*, extension);
}

pub fn pushJump(self: *State, loop: LoopState) !void {
    try self.jumps.append(self.alloc.*, loop);
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

pub fn memPeek(self: *State, addr: usize) !Value {
    if (addr >= self.memory.len) return error.PeekOutOfBounds;

    for (self.extensions.items) |ext| {
        if (addr == ext.address) {
            return ext.getValue(addr);
        }
    }

    return self.memory[addr];
}

pub fn memPoke(self: *State, addr: usize, value: Value) !void {
    if (addr >= self.memory.len) return error.PokeOutOfBounds;

    for (self.extensions.items) |ext| {
        if (addr == ext.address) {
            ext.setValue(addr, value);
        }
    }
    self.memory[addr] = value;
}

pub fn concat(self: *State, val1: Value, val2: Value) ![]const u8 {
    const val1str = try val1.toString(self.alloc);
    const val2str = try val2.toString(self.alloc);

    const output = try std.fmt.allocPrint(self.alloc.*, "{s}{s}", .{
        val1str,
        val2str,
    });

    self.alloc.free(val1str);
    self.alloc.free(val2str);

    try self.strings.append(self.alloc.*, output);
    return output;
}

pub fn allocString(self: *State, len: usize) ![]u8 {
    const buf = try self.alloc.alloc(u8, len);
    try self.strings.append(self.alloc.*, buf);
    return buf;
}

pub fn allocArray(self: *State, dim: usize) !Value {
    const array = try Array.init(self.alloc, dim);
    try self.arrays.append(self.alloc.*, array);
    return Value{ .array = array };
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
    array: Array,

    //My BASIC implementation considers booleans to be 1 for true, all else for false.
    //I dislike the C-ism of "anything non-0 is true"
    pub const TRUE: Value = Value{ .number = 1 };
    pub const FALSE: Value = Value{ .number = 0 };

    pub fn toString(self: *const Value, alloc: *const Alloc) ![]const u8 {
        return switch (self.*) {
            .number => |num| std.fmt.allocPrint(alloc.*, "{}", .{num}),
            .string => |s| try alloc.dupe(u8, s),
            .array => |arr| {
                var buf = try std.ArrayList(u8).initCapacity(alloc.*, arr.array.len * 3);
                const writer = buf.writer(alloc.*);
                try std.fmt.format(writer, "[", .{});
                for (arr.array, 0..) |el, idx| {
                    if (el == .array) {
                        try std.fmt.format(writer, "ARRAY({})", .{el.array.array.len});
                    } else {
                        if (el == .string) try std.fmt.format(writer, "\"", .{});
                        const elStr = try el.toString(alloc);
                        try std.fmt.format(writer, "{s}", .{elStr});
                        alloc.free(elStr);
                        if (el == .string) try std.fmt.format(writer, "\"", .{});
                    }
                    if (idx < arr.array.len - 1) {
                        try std.fmt.format(writer, ", ", .{});
                    }
                }
                try std.fmt.format(writer, "]", .{});

                const strRep = try alloc.dupe(u8, buf.items);
                buf.deinit(alloc.*);
                return strRep;
            },
        };
    }
};

const Array = struct {
    array: []Value,

    pub fn init(alloc: *const Alloc, len: usize) !Array {
        const array = try alloc.*.alloc(Value, len);
        for (0..len) |i| array[i] = Value{ .number = 0 };

        return .{
            .array = array,
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

pub const MemoryExtension = struct {
    address: usize,
    getValue: *const fn (usize) Value,
    setValue: *const fn (usize, Value) void,
};
