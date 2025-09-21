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
                // for (self.tokens[1..]) |tok| {
                //     try switch (tok) {
                //         .string => |str| writer.interface.print("{s}", .{str[1 .. str.len - 1]}),
                //         .number => |num| writer.interface.print("\t{}", .{num}),
                //         .ident => |ident| writer.interface.print("{?}", .{state.valueOf(ident)}),
                //         .operator => |op| if (op == Operator.Comma) continue,
                //         else => return error.SyntaxError,
                //     };
                // }
                const value = try eval(&self.tokens[1], self.tokens[2..], state, null);
                std.log.info("{any}", .{value});
                try writer.interface.print("\n", .{});
            },
            else => {},
        },
        else => {},
    }

    try writer.interface.flush();
}

fn eval(current: *const Token, rest: []const Token, state: *State, acc: ?Value) !Value {
    // std.log.info("{any} {any} {any}", .{ current, rest, acc });

    var accNext: ?Value = null;
    var nextToken: usize = 0;
    var nextArgBase: usize = 1;
    if (acc == null) {
        accNext = toValue(current, state);
        if (accNext == null) {
            return error.SyntaxError;
        }
    } else {
        switch (current.*) {
            .operator => |op| {
                nextToken = 1;
                nextArgBase = 2;
                const next = toValue(&rest[0], state);
                switch (op) {
                    .Plus => {
                        if (acc == null or acc.? != Value.number or next == null or next.? != Value.number) return error.SyntaxErrorPlus;
                        accNext = Value{ .number = acc.?.number + next.?.number };
                    },
                    .Sub => {
                        if (acc == null or acc.? != Value.number or next == null or next.? != Value.number) return error.SyntaxErrorSub;
                        accNext = Value{ .number = acc.?.number - next.?.number };
                    },
                    .Mul => {
                        if (acc == null or acc.? != Value.number or next == null or next.? != Value.number) return error.SyntaxErrorMul;
                        accNext = Value{ .number = acc.?.number * next.?.number };
                    },
                    .Div => {
                        if (acc == null or acc.? != Value.number or next == null or next.? != Value.number) return error.SyntaxErrorDiv;
                        accNext = Value{ .number = acc.?.number / next.?.number };
                    },
                    .Comma => {
                        if (acc == null or acc.? != Value.string or next == null) return error.SyntaxErrorComma;
                        // accNext = Value{ .string = std.}
                        accNext = Value{ .string = try state.concat(acc.?, next.?) };
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    if (rest.len == 0 or nextToken >= rest.len) {
        if (accNext) |output| {
            return output;
        }

        return error.WhatTheFuck;
    }
    return eval(&rest[nextToken], rest[nextArgBase..], state, accNext);
}

fn toValue(token: *const Token, state: *State) ?Value {
    return switch (token.*) {
        .ident => |id| state.valueOf(id),
        .number => |num| Value{ .number = num },
        .string => |str| Value{ .string = str },
        else => null,
    };
}
