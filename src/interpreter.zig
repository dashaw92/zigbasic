const std = @import("std");
const List = std.ArrayList;
const Alloc = std.mem.Allocator;

const Lexer = @import("lexer.zig");
const State = @import("state.zig");
const Value = State.Value;
const Statement = @import("statement.zig");
const TokenStream = Statement.TokenStream;

const Interpreter = @This();

//NB: lexer must remain alive as Statements slice the tokens directly
//This()::deinit will deinit the lexer
lexer: Lexer,
program: List(Statement),
state: State,
alloc: *const std.mem.Allocator,

pub fn init(alloc: *const Alloc, src: []const u8) !Interpreter {
    var lexer = try Lexer.init(src, alloc);
    try lexer.lex();

    const program = try List(Statement).initCapacity(alloc.*, 256);
    const state = try State.init(alloc);

    var self = Interpreter{
        .lexer = lexer,
        .program = program,
        .state = state,
        .alloc = alloc,
    };

    try self.buildStatements();
    return self;
}

pub fn getState(self: *Interpreter) *State {
    return &self.state;
}

pub fn deinit(self: *Interpreter) void {
    self.state.deinit();
    self.program.deinit(self.alloc.*);
    self.lexer.deinit();
}

//Groups all tokens from the lexed source into statements, aka reconstructs the lines
fn buildStatements(self: *Interpreter) !void {
    //The next line number available. It's automatically incremented per-line,
    //so the resulting statements maintain a stable ordering via Statement::line.
    var lineNumber: usize = 0;

    //The edges of the current statement. Statements are stored as slices into the lexer's
    //token list to avoid allocating more memory for existing values.
    var start: usize = 0;
    var end: usize = 0;

    for (self.lexer.tokens.items) |token| {
        defer end += 1;

        switch (token) {
            //Upon hitting a newline, the current group can be stored in the statement list.
            //Handles bookkeeping for line numbers.
            .newline => {
                const firstToken = self.lexer.tokens.items[start];
                if (firstToken == .number) {
                    lineNumber = @max(lineNumber + 1, @as(usize, @intFromFloat(firstToken.number)));
                    start += 1;
                }

                try self.program.append(self.alloc.*, .{
                    .line = lineNumber,
                    .stream = TokenStream.init(self.lexer.tokens.items[start..end]),
                });

                start = end + 1;
                lineNumber += 1;
            },
            else => {},
        }
    }
}

pub fn run(self: *Interpreter) !void {
    var maxIdx: usize = 0;
    var lineToIdx = std.AutoHashMap(usize, usize).init(self.alloc.*);
    defer lineToIdx.deinit();
    for (0.., self.program.items) |i, stmt| {
        try lineToIdx.put(stmt.line, i);

        maxIdx = i;
    }

    var i: usize = 0;
    while (i <= maxIdx) {
        try self.program.items[i].exec(&self.state);

        if (self.state.isHalted()) break;

        if (self.state.jumpBack) |target| {
            i = lineToIdx.get(target) orelse return error.InvalidLineTarget;
            self.state.jumpBack = null;
            continue;
        }

        i += 1;
    }

    std.log.info("*** Finished ***", .{});
}
