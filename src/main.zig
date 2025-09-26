const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\FOR I=1 TO 10
    \\X = I * 2
    \\PRINT "I = ", I, " and X = ", X, "!"
    \\IF I > 3 THEN 6
    \\NEXT I
    \\END
    \\PRINT "!"
    \\GOTO 0
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
