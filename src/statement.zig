const Lexer = @import("lexer.zig");
const Keyword = Lexer.Keyword;
const Operator = Lexer.Operator;
const Token = Lexer.Token;
const State = @import("state.zig");

const Statement = @This();

line: usize,
tokens: []const Token,

pub fn eval(self: *const Statement, state: *State) !void {
    const command = self.tokens[0];
    _ = state.valueOf("X");
    switch (command) {
        .keyword => |kw| switch (kw) {
            .Print => {},
            else => {},
        },
        else => {},
    }
}
