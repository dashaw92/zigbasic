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
                const value = try eval(&self.tokens[1], self.tokens[2..], state, null);
                try switch (value) {
                    .number => |n| writer.interface.print("{}", .{n}),
                    .string => |s| writer.interface.print("{s}", .{s}),
                };
                try writer.interface.print("\n", .{});
            },
            .For => {
                if (self.tokens[1] != .ident) return error.ForMissingIdent;
                const ident = self.tokens[1].ident;
                if (self.tokens[2] != .operator or self.tokens[2].operator != .Equal) return error.ForAssignmentError;

                const startRange = toValue(&self.tokens[3], state);
                if (self.tokens[4] != .keyword or self.tokens[4].keyword != .To) return error.ForAssignmentError;
                const endRange = toValue(&self.tokens[5], state);

                if (startRange == null or endRange == null or startRange.? != .number or endRange.? != .number) return error.ForInvalidRange;

                try state.set(ident, startRange.?);
                try state.pushJump(.{
                    .targetLine = self.line,
                    .ident = ident,
                    .step = 1,
                    .start = startRange.?.number,
                    .stop = endRange.?.number,
                });
            },
            .Next => {
                if (self.tokens[1] != .ident) return error.NextMissingIdent;
                const ident = self.tokens[1].ident;
                const loop = state.peekJump();
                if (loop == null) return error.AnomalousNext;
                if (!std.mem.eql(u8, ident, loop.?.ident)) return error.NextMismatchedIdents;

                const current = state.valueOf(ident);
                if (current == null or current.? != .number) return error.NextBadLoopControl;

                const next = current.?.number + loop.?.step;
                if (next > loop.?.stop) {
                    _ = state.popJump();
                    state.drop(ident);
                } else {
                    try state.set(ident, Value{ .number = next });
                    state.jumpBack = loop.?.targetLine;
                }
            },
            .Goto => {
                const target = toValue(&self.tokens[1], state);
                if (target == null or target.? != .number) return error.GotoBadJump;

                state.jumpBack = @intFromFloat(target.?.number);
            },
            else => {},
        },
        else => {},
    }

    try writer.interface.flush();
}

fn eval(current: *const Token, rest: []const Token, state: *State, acc: ?Value) !Value {
    //State of the accumulator after running this step of the recursion
    var accNext: ?Value = null;
    //Bookkeeping for wrangling the current and rest values for the next step of recursion
    var nextToken: usize = 0;
    var nextArgBase: usize = 1;

    //If there's nothing currently on the "stack", treat literals differently and push them directly
    //into the accumulator.
    if (acc == null) {
        accNext = toValue(current, state);
        //Any null here means the current token is a keyword or operator
        //TODO: Have yet to decide how to handle negatives- should the lexer handle this?
        //If not, this is where it should be checked and handled.
        if (accNext == null) {
            //TODO: These errors will come back to bite me in the ass.
            return error.SyntaxError;
        }
    } else {
        //Value is present in accumulator, so normal parsing occurs
        switch (current.*) {
            .operator => |op| {
                nextToken = 1;
                nextArgBase = 2;
                const next = toValue(&rest[0], state);

                if (acc != null and acc.? == .number and next != null and next.? == .number) {
                    if (doMathOp(op, acc.?.number, next.?.number)) |result| {
                        accNext = Value{ .number = result };
                    }
                } else {
                    switch (op) {
                        .Comma => {
                            if (acc == null or acc.? != Value.string or next == null) return error.SyntaxErrorComma;

                            if (next.? == .string) {
                                accNext = Value{ .string = try state.concat(acc.?, next.?) };
                            } else {
                                var end: usize = 0;
                                while (end < rest.len and (rest[end] == .number or rest[end] == .operator)) : (end += 1) {}

                                const group = try eval(&rest[0], rest[0..end], state, next);
                                accNext = Value{ .string = try state.concat(acc.?, group) };
                                nextToken = end;
                                nextArgBase = end + 1;
                            }
                        },
                        else => {},
                    }
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

fn doMathOp(op: Operator, a: f64, b: f64) ?f64 {
    const eps = std.math.floatEps(f64);
    return switch (op) {
        .Plus => a + b,
        .Sub => a - b,
        .Mul => a * b,
        .Div => a / b,
        .Mod => @mod(a, b),
        .Pow => std.math.pow(f64, a, b),
        .DoubleEq => if (@abs(a - b) < eps) 1 else 0,
        .NotEq => if (@abs(a - b) > eps) 1 else 0,
        .Leq => if (a <= b) 1 else 0,
        .Geq => if (a >= b) 1 else 0,
        .Lt => if (a < b) 1 else 0,
        .Gt => if (a > b) 1 else 0,
        else => null,
    };
}
