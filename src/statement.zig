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
        //Variable assignment
        //X = (expression)
        .ident => |id| {
            stream.consumeOp(.Equal) catch return error.AssignmentExpectedEqual;
            const value = evalSubslice(&stream, state) orelse return error.AssignmentError;
            try state.set(id, value);
        },
        .keyword => |kw| switch (kw) {
            //PRINT (expression)
            .Print => {
                const value = try eval(&stream, state, null);
                try switch (value) {
                    .number => |n| writer.interface.print("{}", .{n}),
                    .string => |s| writer.interface.print("{s}", .{s}),
                };
                try writer.interface.print("\n", .{});
            },
            //FOR (ident) = (expression) TO (expression) [STEP (expression)]
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
            //NEXT (ident)
            //If the ident provided doesn't match the most recent loop's ident, the
            //NEXT is mismatched and incorrect. For any given FOR loop, the matching NEXT
            //statement must be the first NEXT encountered following it.
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
            //GOTO (expression)
            //Unlike NEXT, this also clears loop states. Not sure why, but it seems to work out.
            //IF is also similar in this.
            .Goto => {
                const target = evalSubslice(&stream, state) orelse return error.GotoBadJump;
                state.jumpBack = @intFromFloat(target.number);
                state.clearLoops();
            },
            //IF (expr. A) THEN (expr. B)
            //If expr. A is approx. equal to Value.TRUE (1.0), jump to the line evaluated from expr. B.
            //Could implement an optional ELSE clause, but I don't think it's needed because control flow jumps past the next line anyways.
            .If => {
                const cond = evalSubslice(&stream, state) orelse return error.IfMissingCondition;
                stream.consumeKeyword(.Then) catch return error.IfMissingThen;
                const target = evalSubslice(&stream, state) orelse return error.IfMissingTarget;
                if (floatEq(cond.number, Value.TRUE.number)) {
                    state.jumpBack = @intFromFloat(target.number);
                    state.clearLoops();
                }
            },
            //Immediately ends intepretation unconditionally.
            .End => {
                state.setHalted();
            },
            //PEEK (expression) TO (ident)
            //value returned is stored in ident
            .Peek => {
                const value = evalSubslice(&stream, state) orelse return error.PeekInvalidExpression;
                stream.consumeKeyword(.To) catch return error.PeekMissingTo;
                const ident = stream.consumeIdent() catch return error.PeekMissingIdent;

                const memory = state.memPeek(@intFromFloat(value.number)) catch return error.PeekMemoryError;
                try state.set(ident, memory);
            },
            //POKE (expr. A) TO (expr. B)
            //memory at (expr. B) is set to (expr. A)
            .Poke => {
                const value = evalSubslice(&stream, state) orelse return error.PokeMissingValue;
                stream.consumeKeyword(.To) catch return error.PokeMissingTo;
                const target = evalSubslice(&stream, state) orelse return error.PokeMissingTarget;
                state.memPoke(@intFromFloat(target.number), value) catch return error.PokeMemoryError;
            },
            else => {},
        },
        else => {},
    }

    try writer.interface.flush();
}

fn evalSubslice(stream: *TokenStream, state: *State) ?Value {
    var subslice = stream.subGroup() orelse return null;
    return eval(&subslice, state, null) catch return null;
}

fn eval(stream: *TokenStream, state: *State, acc: ?Value) !Value {
    //State of the accumulator after running this step of the recursion
    var accNext: ?Value = null;

    switch (stream.pop().?.*) {
        //If the next token is a lit (number, ident, string) and acc is not null, syntax error.
        //This is only a valid token when starting a new statement as it's an implicit a push operation onto the stack.
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
            //Comma acts as the string concatenation operator
            //state.concat() calls toString on both provided values
            //so it doesn't matter if acc is not a string
            .Comma => {
                //can't concat null
                if (acc == null) return error.SyntaxErrorComma;

                const group = evalSubslice(stream, state) orelse return error.CommaMissingValue;
                accNext = Value{ .string = try state.concat(acc.?, group) };
            },
            //Parentheses can appear in evaluation in two positions:
            //(A + B) * (C + D)
            //^
            // we're here
            .LeftParen => {
                var group = stream.groupParens() orelse return error.MismatchedParenthesis;
                accNext = try eval(&group, state, null);
            },
            else => {
                switch (stream.pop().?.*) {
                    //... but if a '(' appears here...
                    //(A + B) * (C + D)
                    //        ^
                    //        now we're here, with '(' as the next token.
                    .operator => |opNext| if (opNext == .LeftParen) {
                        var group = stream.groupParens() orelse return error.MismatchedParenthesis;
                        const groupVal = try eval(&group, state, null);
                        //I think only malformed BASIC can bypass this, and I only care about the
                        //interpreter working on proper code.
                        if (doMathOp(op, acc.?.number, groupVal.number)) |result| {
                            accNext = Value{ .number = result };
                        }
                    },
                    else => |n| {
                        const value = toValue(&n, state);
                        if (acc != null and acc.? == .number and value != null and value.? == .number) {
                            if (doMathOp(op, acc.?.number, value.?.number)) |result| {
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

        return error.EvaluatedToNothing;
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
            .number => |n| floatEq(n, Value.TRUE),
            .ident => |id| if (state.valueOf(id)) |idValue| switch (idValue) {
                .number => |n| floatEq(n, Value.TRUE),
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
        .DoubleEq => if (floatEq(a, b)) Value.TRUE.number else Value.FALSE.number,
        .NotEq => if (!floatEq(a, b)) Value.TRUE.number else Value.FALSE.number,
        .Leq => if (a <= b) Value.TRUE.number else Value.FALSE.number,
        .Geq => if (a >= b) Value.TRUE.number else Value.FALSE.number,
        .Lt => if (a < b) Value.TRUE.number else Value.FALSE.number,
        .Gt => if (a > b) Value.TRUE.number else Value.FALSE.number,
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

    //Is the cursor at the end of the token slice?
    fn atEnd(self: *Self) bool {
        return self.cursor >= self.slice.len;
    }

    //Return the next token but don't increment the cursor
    fn peek(self: *Self) ?*const Token {
        if (self.atEnd()) return null;
        return &self.slice[self.cursor];
    }

    //Return the next token and increment the cursor
    fn pop(self: *Self) ?*const Token {
        if (self.atEnd()) return null;
        const current = self.peek();
        self.cursor += 1;
        return current;
    }

    //If the current token is the provided keyword, consume it.
    //Else error.
    fn consumeKeyword(self: *Self, kw: Keyword) !void {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .keyword or tok.?.*.keyword != kw) return error.ExpectedKeyword;
        self.cursor += 1;
    }

    //If the current token is an ident, consume and return it.
    //Else error.
    fn consumeIdent(self: *Self) ![]const u8 {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .ident) return error.ExpectedIdent;
        self.cursor += 1;
        return tok.?.ident;
    }

    //If the current token is the provided operator, consume it.
    //Else error.
    fn consumeOp(self: *Self, op: Operator) !void {
        if (self.atEnd()) return error.EndOfTokens;
        const tok = self.peek();
        if (tok == null or tok.?.* != .operator or tok.?.*.operator != op) return error.ExpectedOperator;
        self.cursor += 1;
    }

    //Returns a child TokenStream of all tokens up to the next boundary token, i.e. the next keyword:
    //IF A + B * C < D THEN
    //   ^^^^^^^^^^^^^ ^^^^
    //   subGroup      boundary token
    fn subGroup(self: *Self) ?TokenStream {
        if (self.atEnd()) return null;
        const start = self.cursor;

        while (!self.atEnd()) : (self.cursor += 1) {
            const current = self.peek();
            switch (current.?.*) {
                .keyword => break,
                else => continue,
            }
        }

        const subslice = self.slice[start..self.cursor];
        return TokenStream.init(subslice);
    }

    //Return a child TokenStream containing all tokens between
    //a current parenthesis group. This is separate from subGroup because
    //subGroup is a generally applicable function used wherever statements can be
    //nested, whereas parentheses are optionally included in said statements.
    //This function should only be called when the current token is a LeftParen.
    fn groupParens(self: *Self) ?TokenStream {
        if (self.atEnd()) return null;
        //If the current token is (, consume it
        _ = self.consumeOp(.LeftParen) catch {};
        const start = self.cursor;
        //Track the depth of parenths to ensure nesting works properly
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

        //If depth isn't 0 at this point, the stream ran out of tokens before finding
        //the matching right parenthesis.
        if (depth != 0) return null;
        //Does not contain the left or right parentheses
        const slice = self.slice[start..self.cursor];
        //Consume the right parenthesis
        _ = self.consumeOp(.RightParen) catch {};
        return TokenStream.init(slice);
    }
};
