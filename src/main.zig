const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\10 FOR I = 48 TO 126
    \\20 PRINTNL CHR(I), " "
    \\30 NEXT I
    \\40 PRINT ""
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
