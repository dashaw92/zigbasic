const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\FOR I=1 TO 10
    \\PRINT "I = ", I, "!"
    \\IF I > 3 THEN 5
    \\NEXT I
    \\END
    \\PRINT "If works!"
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
