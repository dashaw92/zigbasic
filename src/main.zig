const std = @import("std");
const basic = @import("zigbasic_lib");
const Interpreter = basic.Interpreter;

const src =
    \\10 FOR I = 0 TO 1000
    \\20 POKE (I % 2) TO 19
    \\30 NEXT I
    \\40 GOTO 10
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.fs.File.stdout();
    var out_handle = stdout.writer(&.{});
    const stdin = std.fs.File.stdin();
    var in_handle = stdin.reader(&.{});
    const io = basic.IO{
        .out = &out_handle.interface,
        .in = &in_handle.interface,
    };

    var int = try Interpreter.init(&alloc, io, src);
    defer int.deinit();
    try int.state.registerExtension(.{
        .address = 19,
        .getValue = getGPIO19,
        .setValue = setGPIO19,
    });

    try int.run();
}

fn getGPIO19(_: usize) basic.Value {
    return basic.Value.TRUE;
}

fn setGPIO19(_: usize, v: basic.Value) void {
    switch (v) {
        .number => |n| if (n < 1.0) std.log.info("{}", .{n}) else std.log.info("{}", .{n}),
        else => {},
    }
}
