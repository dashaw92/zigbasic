const std = @import("std");
const Alloc = std.mem.Allocator;

const Keyword = enum {
    Print,
    Let,
    If,
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
};

const Operator = enum {
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
};

const Token = union(enum) {
    number: f64,
    operator: Operator,
    keyword: Keyword,
    string: str,
    ident: str,
};

const str = []const u8;
pub const Lexer = struct {
    source: str,
    pos: usize,
    program: std.ArrayList(Token),
    alloc: std.mem.Allocator,

    pub fn init(source: str, alloc: *const Alloc) !Lexer {
        const program = try std.ArrayList(Token).initCapacity(alloc.*, 256);
        return .{ .source = source, .pos = 0, .program = program, .alloc = alloc.* };
    }

    pub fn deinit(self: *Lexer) void {
        self.program.deinit(self.alloc);
    }

    pub fn lex(self: *Lexer) !void {
        while (try self.nextToken()) {}
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

    fn consumeWhitespace(self: *Lexer) !void {
        while (!self.isEof() and std.ascii.isWhitespace(self.peek().?)) : (self.next()) {}
    }

    fn consumeNumber(self: *Lexer) !Token {
        const begin = self.pos;
        while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}
        if (!self.isEof() and self.peek().? == '.') {
            self.next();
            while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}
            self.next();
        }

        const literal = self.source[begin..self.pos];
        const number = try std.fmt.parseFloat(f64, literal);

        return .{ .number = number };
    }

    fn consumeAlpha(self: *Lexer) !Token {
        const begin = self.pos;
        while (!self.isEof() and !std.ascii.isWhitespace(self.source[self.pos])) : (self.next()) {}
        const literal = self.source[begin..self.pos];
        if (Lexer.isKeyword(literal)) |keyword| {
            return .{ .keyword = keyword };
        }

        return .{ .ident = literal };
    }

    fn consumeStringLit(self: *Lexer) !Token {
        const begin = self.pos;
        self.next();
        while (!self.isEof() and self.source[self.pos] != '"') : (self.next()) {}
        self.next();
        const string = self.source[begin..self.pos];

        return .{ .string = string };
    }

    // fn readNumber(self: *Lexer) !usize {
    //     const begin = self.pos;
    //     while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}
    //     const literal = self.source[begin..self.pos];

    //     const number = try std.fmt.parseUnsigned(usize, literal, 10);
    //     return number;
    // }

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

        try self.consumeWhitespace();

        const tok =
            if (std.ascii.isDigit(self.peek().?)) block: {
                break :block try self.consumeNumber();
            } else if (self.peek().? == '"') block: {
                break :block try self.consumeStringLit();
            } else block: {
                if (self.isOperator()) |op| {
                    self.next();

                    break :block Token{ .operator = op };
                }

                break :block try self.consumeAlpha();
            };

        try self.program.append(self.alloc, tok);
        return true;
    }
};
