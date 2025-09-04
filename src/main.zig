const std = @import("std");
const lib = @import("zigbasic_lib");

const src =
    \\ PRINT Hello
    \\ FOR I=0 TO 20
    \\ PRINT Hi
    \\ NEXT I
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = [_]u8{0} ** 1024;
    while (true) {
        buffer = [_]u8{0} ** 1024;
        const b = stdin.readUntilDelimiter(&buffer, '\n') catch break;
        if (std.ascii.eqlIgnoreCase(b, "/quit")) break;

        var lexer = lib.Lexer.init(b, &alloc);
        defer lexer.deinit();

        try lexer.lex();
        for (lexer.tokens.items) |token| {
            std.log.info("{}", .{token.token});
        }
    }
}
