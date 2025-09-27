const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\10 X = ARRAY(13)
    \\20 Y = ARRAY(13) + X
    \\21 FOR I = 0 TO LEN(Y) - 1
    \\25 Y[I] = CHR(INT("A") + I)
    \\29 NEXT I 
    \\30 PRINT "Hello ", Y
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
