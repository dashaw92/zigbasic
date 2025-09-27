const std = @import("std");
const Alloc = std.mem.Allocator;

const Lexer = @This();

pub const Keyword = enum {
    Print,
    PrintNl, //same as print but with no newline
    Let,
    If,
    Then,
    Next,
    For,
    To,
    Step,
    Goto,
    Peek,
    Poke,
    Gosub,
    Return,
    End,
    Rem,
};

pub const Operator = enum {
    Plus,
    Sub,
    Div,
    Mul,
    Pow,
    Mod,
    Equal,
    Not,
    Lt,
    Gt,
    Leq,
    Geq,
    DoubleEq,
    NotEq,
    Comma,
    LeftParen,
    RightParen,
    LeftSquare,
    RightSquare,
};

pub const Function = enum {
    Abs,
    Len,
    Chr,
    Int,
    Lcase,
    Ucase,
    Array,
    Type,
    Sin,
    Cos,
    Tan,
    Sqrt,
    Floor,
    Ceil,
    Deg,
    Rad,
};

const str = []const u8;

pub const Token = union(enum) {
    number: f64,
    operator: Operator,
    keyword: Keyword,
    string: str,
    ident: str,
    function: Function,
    newline,
};

source: str,
pos: usize,
tokens: std.ArrayList(Token),
alloc: *const Alloc,

pub fn init(source: str, alloc: *const Alloc) !Lexer {
    const tokens = try std.ArrayList(Token).initCapacity(alloc.*, 256);
    return .{ .source = source, .pos = 0, .tokens = tokens, .alloc = alloc };
}

pub fn deinit(self: *Lexer) void {
    for (self.tokens.items) |token| {
        switch (token) {
            .ident => |ident| self.alloc.*.free(ident),
            .string => |string| self.alloc.*.free(string),
            else => {},
        }
    }
    self.tokens.deinit(self.alloc.*);
}

pub fn lex(self: *Lexer) !void {
    while (try self.nextToken()) {}
    try self.tokens.append(self.alloc.*, Token.newline);
}

fn isEof(self: *Lexer) bool {
    return self.pos >= self.source.len;
}

fn peek(self: *Lexer) ?u8 {
    if (self.isEof()) {
        return null;
    }

    return self.source[self.pos];
}

fn next(self: *Lexer) void {
    if (self.isEof()) {
        return;
    }

    self.pos += 1;
}

fn isKeyword(buf: str) ?Keyword {
    const eq = std.ascii.eqlIgnoreCase;

    //Enumerate all possible keywords in the enum and compare their name to the provided string
    //Case is ignored because it's BASIC- requires all variant names to match their source representation.
    inline for (@typeInfo(Keyword).@"enum".fields) |field| {
        if (eq(buf, field.name)) {
            return @enumFromInt(field.value);
        }
    }

    return null;
}

fn isFunction(buf: str) ?Function {
    const eq = std.ascii.eqlIgnoreCase;
    inline for (@typeInfo(Function).@"enum".fields) |field| {
        if (eq(buf, field.name)) {
            return @enumFromInt(field.value);
        }
    }

    return null;
}

fn consumeWhitespace(self: *Lexer) !bool {
    while (!self.isEof() and std.ascii.isWhitespace(self.peek().?)) {
        defer self.next();
        if (nextIs(self.peek(), '\n')) {
            return true;
        }
    }

    return false;
}

fn consumeNumber(self: *Lexer) !Token {
    const begin = self.pos;

    while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}
    if (!self.isEof() and self.peek().? == '.') {
        self.next();
        while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}
    }

    const literal = self.source[begin..self.pos];
    const number = try std.fmt.parseFloat(f64, literal);

    return .{ .number = number };
}

fn consumeAlpha(self: *Lexer) !Token {
    const begin = self.pos;
    while (!self.isEof() and (std.ascii.isAlphanumeric(self.peek().?) or self.peek().? == '_')) : (self.next()) {}
    const literal = self.source[begin..self.pos];

    if (begin == self.pos) {
        return error.InvalidToken;
    }

    if (isKeyword(literal)) |keyword| {
        if (keyword == .Rem) {
            while (!self.isEof() and self.peek().? != '\n') : (self.next()) {}
        }
        return .{ .keyword = keyword };
    }

    if (!self.isEof() and self.peek().? == '(') {
        if (isFunction(literal)) |function|
            return .{ .function = function };
    }

    //Once lexing is done, can't assume the provided source code
    //will remain alive.
    const ownedCopy = try self.alloc.*.dupe(u8, literal);
    return .{ .ident = ownedCopy };
}

fn consumeStringLit(self: *Lexer) !Token {
    const begin = self.pos;
    self.next();
    while (!self.isEof() and self.source[self.pos] != '"') : (self.next()) {}
    self.next();
    const string = self.source[begin + 1 .. self.pos - 1];

    //Once lexing is done, can't assume the provided source code
    //will remain alive.
    const ownedCopy = try self.alloc.*.dupe(u8, string);
    return .{ .string = ownedCopy };
}

fn nextIs(nextCh: ?u8, opt: u8) bool {
    if (nextCh) |ch| {
        return ch == opt;
    }
    return false;
}

fn isOperator(self: *Lexer) ?Operator {
    if (self.isEof()) {
        return null;
    }

    const current = self.source[self.pos];
    var nextCh: ?u8 = null;
    if (self.pos + 1 < self.source.len) {
        nextCh = self.source[self.pos + 1];
    }

    switch (current) {
        '+' => return .Plus,
        '*' => return .Mul,
        '/' => return .Div,
        '^' => return .Pow,
        '%' => return .Mod,
        '-' => return .Sub,
        ',' => return .Comma,
        '(' => return .LeftParen,
        ')' => return .RightParen,
        '[' => return .LeftSquare,
        ']' => return .RightSquare,
        '=' => {
            if (nextIs(nextCh, '=')) {
                self.next();
                return .DoubleEq;
            }

            return .Equal;
        },
        '!' => {
            if (nextIs(nextCh, '=')) {
                self.next();
                return .NotEq;
            }

            return .Not;
        },
        '>' => {
            if (nextIs(nextCh, '=')) {
                self.next();
                return .Geq;
            }

            return .Gt;
        },
        '<' => {
            if (nextIs(nextCh, '=')) {
                self.next();
                return .Leq;
            }

            return .Lt;
        },
        else => return null,
    }
}

fn nextToken(self: *Lexer) !bool {
    if (self.isEof()) {
        return false;
    }

    if (try self.consumeWhitespace()) {
        try self.tokens.append(self.alloc.*, Token.newline);
        return true;
    }

    const tok =
        if (std.ascii.isDigit(self.peek().?)) block: {
            break :block try self.consumeNumber();
        } else if (self.peek().? == '"') block: {
            break :block try self.consumeStringLit();
        } else block: {
            if (nextIs(self.peek().?, ':')) {
                self.next();
                break :block Token.newline;
            }

            if (self.isOperator()) |op| {
                self.next();

                break :block Token{ .operator = op };
            }

            break :block try self.consumeAlpha();
        };

    try self.tokens.append(self.alloc.*, tok);
    return true;
}
