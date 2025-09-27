const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\1 X = ARRAY(5)
    \\2 X[0] = ARRAY(2)
    \\3 X[0][0] = X
    \\4 X[0][1] = "Hello"
    \\5 PRINT X[0][0][0][0]
    \\6 PRINT LEN(X)
    \\7 IF TYPE(X) != "string" THEN 20
    \\8 END
    \\20 PRINT "It's not a string!"
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();

    try int.run();
}
