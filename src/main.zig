const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\ 5 REM 180 degrees to radians is ≈ to Pi!
    \\10 PI = RAD(180)
    \\20 PRINT FLOOR(PI * 100) / 100
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
