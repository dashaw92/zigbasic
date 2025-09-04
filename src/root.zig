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

const Line = struct {
    line: usize,
    token: Token,
};

const str = []const u8;
pub const Lexer = struct {
    source: str,
    currentLine: str,
    pos: usize,
    program: std.ArrayList(Line),

    pub fn init(source: str, alloc: *const Alloc) Lexer {
        return .{ .source = source, .currentLine = undefined, .pos = 0, .program = std.ArrayList(Line).init(alloc.*) };
    }

    pub fn deinit(self: Lexer) void {
        self.program.deinit();
    }

    pub fn lex(self: *Lexer) !void {
        var lines = std.mem.splitAny(u8, self.source, "\n");

        while (lines.next()) |line| {
            self.currentLine = line;
            self.pos = 0;
            try self.lexLine();
        }
    }

    fn isEof(self: *Lexer) bool {
        return self.pos >= self.currentLine.len;
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.isEof()) {
            return null;
        }

        return self.currentLine[self.pos];
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

        const literal = self.currentLine[begin..self.pos];
        const number = try std.fmt.parseFloat(f64, literal);

        return .{ .number = number };
    }

    fn consumeAlpha(self: *Lexer) !Token {
        const begin = self.pos;
        while (!self.isEof() and !std.ascii.isWhitespace(self.currentLine[self.pos])) : (self.next()) {}
        const literal = self.currentLine[begin..self.pos];
        if (Lexer.isKeyword(literal)) |keyword| {
            return .{ .keyword = keyword };
        }

        return .{ .ident = literal };
    }

    fn consumeStringLit(self: *Lexer) !Token {
        const begin = self.pos;
        self.next();
        while (!self.isEof() and self.currentLine[self.pos] != '"') : (self.next()) {}
        self.next();
        const string = self.currentLine[begin..self.pos];

        return .{ .string = string };
    }

    fn readNumber(self: *Lexer) !usize {
        const begin = self.pos;
        while (!self.isEof() and std.ascii.isDigit(self.peek().?)) : (self.next()) {}

        const literal = self.currentLine[begin..self.pos];
        const number = try std.fmt.parseUnsigned(usize, literal, 10);
        return number;
    }

    fn nextIs(nextCh: ?u8, opt: u8) bool {
        if (nextCh) |ch| {
            return ch == opt;
        }
        return false;
    }

    fn isOperator(self: *Lexer) ?Operator {
        const current = self.currentLine[self.pos];
        var nextCh: ?u8 = null;
        if (self.pos + 1 < self.currentLine.len) {
            nextCh = self.currentLine[self.pos + 1];
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

    fn lexLine(self: *Lexer) !void {
        const lineNum: usize = self.readNumber() catch 0;
        try self.consumeWhitespace();
        const command = try self.consumeAlpha();

        const tok = Line{ .line = lineNum, .token = command };
        try self.program.append(tok);
    }
};
