const std = @import("std");
const Interpreter = @import("interpreter.zig");
const State = @import("state.zig");
const Value = State.Value;
const MemoryExt = State.MemoryExtension;

const src =
    \\FOR I = 0 TO 3
    \\FOR J = 0 TO 3
    \\PEEK 10 TO X
    \\PRINT 10, " = ", X
    \\NEXT J
    \\NEXT I
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    try int.getState().registerExtension(MemoryExt{
        .address = 10,
        .getValue = getRandom,
        .setValue = setRandom,
    });

    defer int.deinit();

    try int.run();
}

fn getRandom(_: usize) Value {
    var rng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));
    return Value{ .number = rng.random().float(f64) };
}

fn setRandom(_: usize, _: Value) void {}
