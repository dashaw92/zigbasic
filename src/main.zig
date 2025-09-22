const std = @import("std");
const Interpreter = @import("interpreter.zig");

const src =
    \\PRINT "Hello ", "Hello ", 5500 / 2 
    \\FOR I=0 TO 20
    \\PRINT "Hi"
    \\NEXT I
;

pub fn main() !void {
    // var buffer: [1024]u8 = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    // var stdin_reader = std.fs.File.stdin().reader(&buffer);
    // const stdin = &stdin_reader.interface;

    // while (stdin.takeDelimiterExclusive('\n')) |line| {
    // if (std.ascii.eqlIgnoreCase(line, "/quit")) break;

    var int = try Interpreter.init(&alloc, src);
    defer int.deinit();
    for (int.program.items) |stmt| {
        _ = stmt;
        // std.log.info("{any}", .{stmt});
    }

    try int.run();

    // } else |e| {
    // if (e == error.EndOfStream) return;
    // std.log.info("{}", .{e});
    // }
}
