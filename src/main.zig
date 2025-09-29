const std = @import("std");
const basic = @import("zigbasic_lib");
const Interpreter = basic.Interpreter;

const src =
    \\ 5 REM 180 degrees to radians is ≈ to Pi!
    \\10 PI = RAD(180)
    \\20 PRINT FLOOR(PI * 100) / 100
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

    try int.run();
}
