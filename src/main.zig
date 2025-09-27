const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\10 MYSTR = "Hello World!"
    \\20 FOR I = 0 TO LEN(MYSTR) - 1
    \\30 PRINTNL INT(UCASE(MYSTR[I])), " "
    \\40 NEXT I
    \\50 PRINT ""
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
