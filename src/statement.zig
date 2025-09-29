const std = @import("std");

const IO = @import("interpreter.zig").IO;
const Lexer = @import("lexer.zig");
const Keyword = Lexer.Keyword;
const Operator = Lexer.Operator;
const Function = Lexer.Function;
const Token = Lexer.Token;
const State = @import("state.zig");
const Value = State.Value;

const Statement = @This();

line: usize,
stream: TokenStream,

const ArrayAssignment = struct {
    target: Value,
    index: Value,
};

//Statements that assign values to idents should support arbitrary array indexing if the ident is an array.
//This function will iteratively index into arrays until the bottom value is found. If the ident is not an array,
//returns null. Otherwise, the target array and the last evaluated index is returned so statements can correctly
//assign the following expression's value into the array.
fn identMaybeArray(stream: *TokenStream, state: *State, ident: []const u8) !?ArrayAssignment {
    //If the ident is followed by an indexing operator ('['), iterate through the tokens until finished indexing.
    if (stream.nextOpIs(.LeftSquare)) {
        //For assignment, this would normally be fine. However, indexing requires an array (duh), so if the
        //value isn't currently defined, wtf are they trying to do??
        var current = state.valueOf(ident) orelse return error.UnknownIdent;
        var index = Value{ .number = 0 };

        //Likewise, cannot index into anything but an array (string indexing is read-only).
        if (current != .array) return error.InvalidIndexAssignment;
        while (stream.nextOpIs(.LeftSquare) and current == .array) {
            //inner group of current indexing group
            var group = stream.groupToBoundary(.LeftSquare, .RightSquare) orelse return error.MissingClosingSquare;

            //can be any valid expression, so need to eval
            index = try eval(&group, state, null);
            if (index != .number or @as(usize, @intFromFloat(index.number)) >= current.array.array.len) return error.IndexOutOfBounds;

            //Are we finished indexing?
            if (!stream.nextOpIs(.LeftSquare)) break;

            //Nope, update current to reflect this index group's evaluation
            current = current.array.array[@as(usize, @intFromFloat(index.number))];
        }

        return .{ .index = index, .target = current };
    }

    //No '[' in tokenstream after starting ident.
    return null;
}

pub fn exec(self: *const Statement, state: *State, io: *IO) !void {
    var writer = io.out;

    var stream = self.stream;
    stream.reset();
    const command = stream.pop().?;
    switch (command.*) {
        //Variable assignment
        //X = (expression)
        .ident => |id| {
            const array = try identMaybeArray(&stream, state, id);
            if (array != null) {
                stream.consumeOp(.Equal) catch return error.AssignmentExpectedEqual;
                const value = evalSubslice(&stream, state) orelse return error.AssignmentError;
                array.?.target.array.array[@as(usize, @intFromFloat(array.?.index.number))] = value;
                return;
            }

            stream.consumeOp(.Equal) catch return error.AssignmentExpectedEqual;
            const value = evalSubslice(&stream, state) orelse return error.AssignmentError;
            try state.set(id, value);
        },
        .keyword => |kw| switch (kw) {
            //PRINT (expression)
            .Print, .PrintNl => {
                const newline = kw == .Print;
                const value = try eval(&stream, state, null);
                const strRepr = value.toString(state.alloc) catch return error.FailedToAllocStringRepr;
                try writer.print("{s}", .{strRepr});
                state.alloc.free(strRepr);

                if (newline) try writer.print("\n", .{});
                try writer.flush();
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
                if (stream.nextKeywordIs(.Step)) {
                    stream.consumeKeyword(.Step) catch unreachable;
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
                const memory = state.memPeek(@intFromFloat(value.number)) catch return error.PeekMemoryError;
                stream.consumeKeyword(.To) catch return error.PeekMissingTo;
                const ident = stream.consumeIdent() catch return error.PeekMissingIdent;
                const array = try identMaybeArray(&stream, state, ident);
                if (array != null) {
                    array.?.target.array.array[@as(usize, @intFromFloat(array.?.index.number))] = memory;
                    return;
                }

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
            //INPUT (ident)
            .Input => {
                var buf: [1]u8 = [1]u8{0};
                io.in.readSliceAll(&buf) catch |e| {
                    if (e != error.EndOfStream) return error.InputReadError;
                };
                const ident = stream.consumeIdent() catch return error.InputMissingIdent;
                const array = try identMaybeArray(&stream, state, ident);
                if (array != null) {
                    array.?.target.array.array[@as(usize, @intFromFloat(array.?.index.number))] = Value{ .number = @floatFromInt(buf[0]) };
                    return;
                }

                try state.set(ident, Value{ .number = @floatFromInt(buf[0]) });
            },
            else => {},
        },
        else => {},
    }
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
        .function => |func| {
            var group = stream.groupToBoundary(.LeftParen, .RightParen) orelse return error.FunctionMissingArgument;
            const argument = try eval(&group, state, null);
            accNext = function(func, state, argument) orelse return error.FunctionBadCall;
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
                var group = stream.groupToBoundary(.LeftParen, .RightParen) orelse return error.MismatchedParenthesis;
                accNext = try eval(&group, state, null);
            },
            .LeftSquare => {
                if (acc == null) return error.UnexpectedSquareBrackets;

                var group = stream.groupToBoundary(.LeftSquare, .RightSquare) orelse return error.MismatchedSquareBrackets;
                const groupVal = try eval(&group, state, null);
                if (groupVal != .number or groupVal.number < 0) return error.InvalidIndex;

                const index: usize = @intFromFloat(groupVal.number);

                switch (acc.?) {
                    .string => |s| {
                        if (index >= s.len) return error.IndexOutOfBounds;
                        accNext = Value{ .string = s.ptr[index .. index + 1] };
                    },
                    .array => |a| {
                        if (index >= a.array.len) return error.IndexOutOfBounds;
                        accNext = a.array[index];
                    },
                    else => return error.InvalidIndexOnNonIndexable,
                }
            },
            //Same as parentheses
            else => {
                switch (stream.pop().?.*) {
                    //... but if a '(' appears here...
                    //(A + B) * (C + D)
                    //        ^
                    //        now we're here, with '(' as the next token.
                    .operator => |opNext| switch (opNext) {
                        .LeftParen => {
                            var group = stream.groupToBoundary(.LeftParen, .RightParen) orelse return error.MismatchedParenthesis;
                            const groupVal = try eval(&group, state, null);
                            //I think only malformed BASIC can bypass this, and I only care about the
                            //interpreter working on proper code.
                            if (doMathOp(op, state, acc.?, groupVal)) |result| {
                                accNext = result;
                            }
                        },
                        else => {},
                    },
                    else => |n| {
                        const value = outer: switch (n) {
                            .function => {
                                var group = stream.groupToBoundary(.LeftParen, .RightParen) orelse return error.MismatchedParenthesis;
                                const groupVal = try eval(&group, state, null);
                                break :outer function(n.function, state, groupVal) orelse return error.FunctionMissingArgument;
                            },
                            else => toValue(&n, state),
                        };
                        if (acc != null and value != null) {
                            if (doMathOp(op, state, acc.?, value.?)) |result| {
                                accNext = result;
                            }
                        } else return error.InvalidOperation;
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

fn floatMath(op: Operator, a: f64, b: f64) ?f64 {
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

fn doMathOp(op: Operator, state: *State, a: Value, b: Value) ?Value {
    if (a == .number and b == .number) return Value{ .number = floatMath(op, a.number, b.number) orelse return null };
    if (a == .string and b == .string) return switch (op) {
        .DoubleEq => if (std.mem.eql(u8, a.string, b.string)) Value.TRUE else Value.FALSE,
        .NotEq => if (!std.mem.eql(u8, a.string, b.string)) Value.TRUE else Value.FALSE,
        else => null,
    };
    if (a == .array and b == .array and op == .Plus) {
        const newArray = state.allocArray(a.array.array.len + b.array.array.len) catch return null;

        var i: usize = 0;
        for (a.array.array) |el| {
            newArray.array.array[i] = el;
            i += 1;
        }

        for (b.array.array) |el| {
            newArray.array.array[i] = el;
            i += 1;
        }

        return newArray;
    }

    return null;
}

fn function(func: Function, state: *State, arg: Value) ?Value {
    switch (func) {
        .Abs => if (arg == .number) return Value{ .number = @abs(arg.number) },
        .Len => switch (arg) {
            .string => |s| return Value{ .number = @floatFromInt(s.len) },
            .array => |a| return Value{ .number = @floatFromInt(a.array.len) },
            else => return null,
        },
        .Chr => if (arg == .number) {
            var buf = state.allocString(1) catch return null;
            buf[0] = @as(u8, @intFromFloat(arg.number));
            return Value{ .string = buf };
        },
        .Int => if (arg == .string) return Value{ .number = @floatFromInt(arg.string.ptr[0]) },
        .Lcase => if (arg == .string) {
            const buf = state.allocString(arg.string.len) catch return null;
            _ = std.ascii.lowerString(buf, arg.string);
            return Value{ .string = buf };
        },
        .Ucase => if (arg == .string) {
            const buf = state.allocString(arg.string.len) catch return null;
            _ = std.ascii.upperString(buf, arg.string);
            return Value{ .string = buf };
        },
        .Array => if (arg == .number) return state.allocArray(@intFromFloat(arg.number)) catch return null,
        .Type => {
            const name = switch (arg) {
                .number => "number",
                .string => "string",
                .array => "array",
            };

            return Value{ .string = name };
        },
        .Sin => if (arg == .number) return Value{ .number = std.math.sin(arg.number) },
        .Cos => if (arg == .number) return Value{ .number = std.math.cos(arg.number) },
        .Tan => if (arg == .number) return Value{ .number = std.math.tan(arg.number) },
        .Ceil => if (arg == .number) return Value{ .number = @ceil(arg.number) },
        .Floor => if (arg == .number) return Value{ .number = @floor(arg.number) },
        .Sqrt => if (arg == .number) return Value{ .number = std.math.sqrt(arg.number) },
        .Deg => if (arg == .number) return Value{ .number = std.math.radiansToDegrees(arg.number) },
        .Rad => if (arg == .number) return Value{ .number = std.math.degreesToRadians(arg.number) },
        .Peek => if (arg == .number) return state.memPeek(@as(usize, @intFromFloat(arg.number))) catch return Value{ .number = 0 },
    }
    return null;
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

    fn nextOpIs(self: *Self, op: Operator) bool {
        return !self.atEnd() and self.peek().?.* == .operator and self.peek().?.*.operator == op;
    }

    fn nextKeywordIs(self: *Self, kw: Keyword) bool {
        return !self.atEnd() and self.peek().?.* == .keyword and self.peek().?.*.keyword == kw;
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
    //a current group. This is separate from subGroup because
    //subGroup is a generally applicable function used wherever statements can be
    //nested, whereas these groups are optionally included in said statements.
    //This function should only be called when the current token is a groupStart.
    fn groupToBoundary(self: *Self, groupStart: Operator, groupEnd: Operator) ?TokenStream {
        if (self.atEnd()) return null;
        //If the current token is (, consume it
        _ = self.consumeOp(groupStart) catch {};
        const start = self.cursor;
        //Track the depth of parenths to ensure nesting works properly
        var depth: usize = 0;
        while (!self.atEnd()) : (self.cursor += 1) {
            const current = self.peek().?.*;
            if (current != .operator) continue;

            const op = current.operator;
            if (op == groupStart) {
                depth += 1;
            } else if (op == groupEnd) {
                if (depth == 0) break;
                depth -= 1;
            }
        }

        //If depth isn't 0 at this point, the stream ran out of tokens before finding
        //the matching end group operator.
        if (depth != 0) return null;
        //Does not contain the grouping operators
        const slice = self.slice[start..self.cursor];
        //Consume the right parenthesis
        _ = self.consumeOp(groupEnd) catch {};
        return TokenStream.init(slice);
    }
};
