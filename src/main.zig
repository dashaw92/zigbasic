const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\Y = 0
    \\IF Y >= (1 - 1) THEN (2 + Y + 1) 
    \\END
    \\PRINT "Y + 2 > 1 :::: ", "Hello", 2 * 2
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
