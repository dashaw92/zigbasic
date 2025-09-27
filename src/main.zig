const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\10 FOR I = 5 TO 10
    \\20 PRINT I
    \\25 IF I > 9 THEN 40
    \\30 NEXT I
    \\31 END
    \\40 PRINT "Ok it worked"
    \\41 GOTO I
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
