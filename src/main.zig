const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\X = 2 + 3 * 2
    \\PRINT X
    \\X = 2 + (3 * (1 + 1))
    \\PRINT X
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
