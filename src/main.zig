const std = @import("std");
const Lexer = @import("lexer.zig");
const Interpreter = @import("interpreter.zig");

const src =
    \\ PRINT "Hello"
    \\ FOR I=0 TO 20
    \\ PRINT "Hi"
    \\ NEXT I
;

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var stdin_reader = std.fs.File.stdin().reader(&buffer);
    const stdin = &stdin_reader.interface;

    while (stdin.takeDelimiterExclusive('\n')) |line| {
        if (std.ascii.eqlIgnoreCase(line, "/quit")) break;

        var lexer = try Lexer.init(line, &alloc);
        defer lexer.deinit();

        try lexer.lex();
        for (lexer.tokens.items) |token| {
            std.log.info("{}", .{token});
        }
    } else |e| {
        if (e == error.EndOfStream) return;
        std.log.info("{}", .{e});
    }
}
