const std = @import("std");

const Lexer = @import("lexer.zig");
const Keyword = Lexer.Keyword;
const Operator = Lexer.Operator;
const Token = Lexer.Token;
const State = @import("state.zig");
const Value = State.Value;

const Statement = @This();

line: usize,
stream: TokenStream,

pub fn exec(self: *const Statement, state: *State) !void {
    const handle = std.fs.File.stdout();
    var writer = handle.writer(&.{});

    var stream = self.stream;
    stream.reset();
    const command = stream.pop().?;
    switch (command.*) {
        .ident => |id| {
            try stream.consumeOp(.Equal);
            const value = evalSubslice(&stream, state) orelse return error.AssignmentError;
            try state.set(id, value);
        },
        .keyword => |kw| switch (kw) {
            .Print => {
                const value = try eval(&stream, state, null);
                try switch (value) {
                    .number => |n| writer.interface.print("{}", .{n}),
                    .string => |s| writer.interface.print("{s}", .{s}),
                };
                try writer.interface.print("\n", .{});
            },
            .For => {
                if (state.peekJump() != null and state.peekJump().?.targetLine == self.line) return;

                const ident = stream.consumeIdent() catch return error.ForMissingIdent;
                stream.consumeOp(.Equal) catch return error.ForAssignmentError;

                const startRange = evalSubslice(&stream, state) orelse return error.ForInvalidStartRange;
                stream.consumeKeyword(.To) catch return error.ForMissingTo;
                const endRange = evalSubslice(&stream, state) orelse return error.ForInvalidStopRange;

                if (startRange != .number or endRange != .number) return error.ForInvalidRange;

                var step: f64 = 1;
                const nextTok = stream.pop();
                if (nextTok != null and nextTok.?.* == .keyword and nextTok.?.*.keyword == .Step) {
                    const providedStep = evalSubslice(&stream, state) orelse return error.ForInvalidStep;
                    step = providedStep.number;
                }

                try state.set(ident, startRange);
                try state.pushJump(.{
                    .targetLine = self.line,
                    .ident = ident,
                    .step = step,
                    .start = startRange.number,
                    .stop = endRange.number,
                });
            },
            .Next => {
                const ident = stream.consumeIdent() catch return error.NextMissingIdent;
                const loop = state.peekJump();
                if (loop == null) return error.AnomalousNext;
                if (!std.mem.eql(u8, ident, loop.?.ident)) return error.NextMismatchedIdents;

                const current = state.valueOf(ident);
                if (current == null or current.? != .number) return error.NextBadLoopControl;

                const next = current.?.number + loop.?.step;
                try state.set(ident, Value{ .number = next });
                if (next > loop.?.stop) {
                    _ = state.popJump();
                } else {
                    state.jumpBack = loop.?.targetLine;
                }
            },
            .Goto => {
                const target = evalSubslice(&stream, state) orelse return error.GotoBadJump;
                state.jumpBack = @intFromFloat(target.number);
                state.clearLoops();
            },
            .If => {
                const cond = evalSubslice(&stream, state) orelse return error.IfMissingCondition;
                try stream.consumeKeyword(.Then);
                const target = evalSubslice(&stream, state) orelse return error.IfMissingTarget;
                if (floatEq(cond.number, 1.0)) {
                    state.jumpBack = @intFromFloat(target.number);
                    state.clearLoops();
                }
            },
            .End => {
                state.setHalted();
            },
            else => {},
        },
        else => {},
    }

    try writer.interface.flush();
}

fn evalSubslice(stream: *TokenStream, state: *State) ?Value {
    var subslice = stream.mathGroup() orelse return null;
    return eval(&subslice, state, null) catch return null;
}

fn eval(stream: *TokenStream, state: *State, acc: ?Value) !Value {
    //State of the accumulator after running this step of the recursion
    var accNext: ?Value = null;

    switch (stream.pop().?.*) {
        .number => |n| {
            if (acc != null) return error.UnexpectedNumberLit;
            accNext = Value{ .number = n };
        },
        .ident => |id| {
            if (acc != null) return error.UnexpectedIdent;
            accNext = state.valueOf(id);
        },
        .string => |str| {
            if (acc != null) return error.UnexpectedStringLit;
            accNext = Value{ .string = str };
        },
        .operator => |op| switch (op) {
            .Comma => {
                const next = toValue(stream.pop().?, state);
                if (acc == null or acc.? != Value.string or next == null) return error.SyntaxErrorComma;

                if (next.? == .string) {
                    accNext = Value{ .string = try state.concat(acc.?, next.?) };
                } else {
                    //because next is taken via pop(), but next is part of the sub-statement
                    stream.rewind(1);
                    const group = evalSubslice(stream, state).?;
                    accNext = Value{ .string = try state.concat(acc.?, group) };
                }
            },
            .LeftParen => {
                var group = stream.groupParens() orelse return error.MismatchedParenthesis;
                accNext = try eval(&group, state, null);
            },
            else => {
                switch (stream.pop().?.*) {
                    .operator => |opNext| if (opNext == .LeftParen) {
                        var group = stream.groupParens() orelse return error.MismatchedParenthesis;
                        const groupVal = try eval(&group, state, null);
                        if (doMathOp(op, acc.?.number, groupVal.number)) |result| {
                            accNext = Value{ .number = result };
                        }
                    },
                    else => |n| {
                        if (acc != null and acc.? == .number and n == .number) {
                            if (doMathOp(op, acc.?.number, n.number)) |result| {
                                accNext = Value{ .number = result };
                            }
                        }
                    },
                }
            },
        },
        else => return error.UnexpectedTokenInEval,
    }

    if (stream.atEnd()) {
        if (accNext) |output| {
            return output;
        }

        return error.WhatTheFuck;
    }
    return eval(stream, state, accNext);
}

fn toValue(token: *const Token, state: *State) ?Value {
    return switch (token.*) {
        .ident => |id| state.valueOf(id),
        .number => |num| Value{ .number = num },
        .string => |str| Value{ .string = str },
        else => null,
    };
}

fn isTrue(value: ?Value, state: *State) bool {
    if (value) |v| {
        return switch (v) {
            .number => |n| floatEq(n, 1),
            .ident => |id| if (state.valueOf(id)) |idValue| switch (idValue) {
                .number => |n| floatEq(n, 1),
                else => false,
            },
            else => false,
        };
    }

    return false;
}

fn floatEq(a: f64, b: f64) bool {
    const eps = std.math.floatEps(f64);
    return @abs(a - b) <= eps;
}

fn doMathOp(op: Operator, a: f64, b: f64) ?f64 {
    return switch (op) {
        .Plus => a + b,
        .Sub => a - b,
        .Mul => a * b,
        .Div => a / b,
        .Mod => @mod(a, b),
        .Pow => std.math.pow(f64, a, b),
        .DoubleEq => if (floatEq(a, b)) 1 else 0,
        .NotEq => if (!floatEq(a, b)) 1 else 0,
        .Leq => if (a <= b) 1 else 0,
        .Geq => if (a >= b) 1 else 0,
        .Lt => if (a < b) 1 else 0,
        .Gt => if (a > b) 1 else 0,
        else => null,
    };
}

pub const TokenStream = struct {
    slice: []const Token,
    cursor: usize,

    const Self = @This();

    pub fn init(slice: []const Token) TokenStream {
        return .{
            .slice = slice,
            .cursor = 0,
        };
    }

    //XXX Must be called or subsequent executions of the same statement will be wonky
    fn reset(self: *Self) void {
        self.cursor = 0;
    }

    fn atEnd(self: *Self) bool {
        return self.cursor >= self.slice.len;
    }

    fn peek(self: *Self) ?*const Token {
        if (self.atEnd()) return null;
        return &self.slice[self.cursor];
    }

    fn pop(self: *Self) ?*const Token {
        if (self.atEnd()) return null;
        const current = self.peek();
        self.cursor += 1;
        return current;
    }

    fn rewind(self: *Self, amount: usize) void {
        if (self.cursor < amount) return;
        self.cursor -= amount;
    }

    fn consumeKeyword(self: *Self, kw: Keyword) !void {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .keyword or tok.?.*.keyword != kw) return error.ExpectedKeyword;
        self.cursor += 1;
    }

    fn consumeIdent(self: *Self) ![]const u8 {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .ident) return error.ExpectedIdent;
        self.cursor += 1;
        return tok.?.ident;
    }

    fn consumeOp(self: *Self, op: Operator) !void {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .operator or tok.?.*.operator != op) return error.ExpectedOperator;
        self.cursor += 1;
    }

    fn mathGroup(self: *Self) ?TokenStream {
        if (self.atEnd()) return null;
        const start = self.cursor;

        while (!self.atEnd()) : (self.cursor += 1) {
            const current = self.peek();
            switch (current.?.*) {
                .keyword => break,
                .operator => |op| if (op == .Comma) break,
                else => continue,
            }
        }

        const subslice = self.slice[start..self.cursor];
        return TokenStream.init(subslice);
    }

    fn groupParens(self: *Self) ?TokenStream {
        if (self.atEnd()) return null;
        _ = self.consumeOp(.LeftParen) catch {};
        const start = self.cursor;
        var depth: usize = 0;
        while (!self.atEnd()) : (self.cursor += 1) {
            const current = self.peek();
            switch (current.?.*) {
                .operator => |op| switch (op) {
                    .LeftParen => depth += 1,
                    .RightParen => {
                        if (depth == 0) break;
                        depth -= 1;
                    },
                    else => continue,
                },
                else => continue,
            }
        }

        if (depth != 0) return null;
        const slice = self.slice[start..self.cursor];
        _ = self.consumeOp(.RightParen) catch {};
        return TokenStream.init(slice);
    }
};
