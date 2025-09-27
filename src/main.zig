const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\10 X = ARRAY(2)
    \\15 X[0] = "Hi"
    \\20 Y = X + ARRAY(5)
    \\20 PRINT "Hello ", Y
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
