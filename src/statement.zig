const std = @import("std");

const Lexer = @import("lexer.zig");
const Keyword = Lexer.Keyword;
const Operator = Lexer.Operator;
const Token = Lexer.Token;
const State = @import("state.zig");
const Value = State.Value;

const Statement = @This();

line: usize,
tokens: []const Token,

pub fn exec(self: *const Statement, state: *State) !void {
    const handle = std.fs.File.stdout();
    var writer = handle.writer(&.{});

    const command = self.tokens[0];
    switch (command) {
        .keyword => |kw| switch (kw) {
            .Print => {
                for (self.tokens[1..]) |tok| {
                    try switch (tok) {
                        .string => |str| writer.interface.print("{s}", .{str[1 .. str.len - 1]}),
                        .number => |num| writer.interface.print("\t{}", .{num}),
                        .ident => |ident| writer.interface.print("{?}", .{state.valueOf(ident)}),
                        .operator => |op| if (op == Operator.Comma) continue,
                        else => return error.SyntaxError,
                    };
                }
                try writer.interface.print("\n", .{});
            },
            else => {},
        },
        else => {},
    }

    try writer.interface.flush();
}
