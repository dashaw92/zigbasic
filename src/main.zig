const std = @import("std");
const basic = @import("zigbasic_lib");
const Interpreter = basic.Interpreter;

const src =
    // \\10 X = ARRAY(10)
    // \\20 I = 0
    // \\30 PRINTNL "Enter something or Q to quit: "
    // \\40 INPUT X[I]
    // \\61 IF X[I] == 10 THEN 40
    // \\60 PRINT X
    // \\50 IF CHR(X[I]) == "q" THEN 80
    // \\51 IF I >= (LEN(X) - 1) THEN 80
    // \\65 I = I + 1
    // \\70 GOTO 30
    // \\80 END
    \\10 X = SQRT(0 - 1)
    \\20 PRINT ISINF(X)
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.fs.File.stdout();
    var out_handle = stdout.writer(&.{});
    const stdin = std.fs.File.stdin();
    var in_handle = stdin.reader(&.{});
    const io = basic.IO{
        .out = &out_handle.interface,
        .in = &in_handle.interface,
    };

    var int = try Interpreter.init(&alloc, io, src);
    defer int.deinit();
    // try int.state.registerExtension(.{
    //     .address = 19,
    //     .getValue = getGPIO19,
    //     .setValue = setGPIO19,
    // });

    try int.run();
}

// fn getGPIO19(_: usize) basic.Value {
//     return basic.Value.TRUE;
// }

// fn setGPIO19(_: usize, v: basic.Value) void {
//     std.log.info("poked with value: {}", .{v});
// }
