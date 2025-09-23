const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\FOR I=1 TO 10 STEP 3
    \\PRINT "I = ", I
    \\GOTO 3
    \\NEXT I
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
