const std = @import("std");
const List = std.ArrayList;
const Alloc = std.mem.Allocator;

const Lexer = @import("lexer.zig");
const State = @import("state.zig");
const Value = State.Value;
const Statement = @import("statement.zig");

const Interpreter = @This();

//NB: lexer must remain alive as Statements slice the tokens directly
//This()::deinit will deinit the lexer
lexer: Lexer,
program: List(Statement),
state: State,
alloc: std.mem.Allocator,

pub fn init(alloc: *const Alloc, src: []const u8) !Interpreter {
    var lexer = try Lexer.init(src, alloc);
    try lexer.lex();

    const program = try List(Statement).initCapacity(alloc.*, 256);
    const state = try State.init(alloc);

    var self = Interpreter{
        .lexer = lexer,
        .program = program,
        .state = state,
        .alloc = alloc.*,
    };

    try self.buildStatements();
    return self;
}

pub fn deinit(self: *Interpreter) void {
    self.state.deinit();
    self.program.deinit(self.alloc);
    self.lexer.deinit();
}

//Groups all tokens from the lexed source into statements, aka reconstructs the lines
fn buildStatements(self: *Interpreter) !void {
    //If true and the first token encountered on the line is a number, it's taken
    //to be the line number of the statement.
    var beginningOfLine = true;
    //The next line number available. If statements omit a line number, the line
    //will be inserted with this value. It's automatically incremented per-line,
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
                try self.program.append(self.alloc, .{
                    .line = lineNumber,
                    .tokens = self.lexer.tokens.items[start..end],
                });

                beginningOfLine = true;
                start = end + 1;
                lineNumber += 1;
            },
            .number => |num| {
                //If this is the first token of the current statement, update
                //the tracked lineNumber field to the provided value.
                if (beginningOfLine) {
                    //Quirk: this will accept floating point numbers, but the fractional parts
                    //are lost. It works fine, so it can stay.
                    lineNumber = @min(lineNumber + 1, @as(usize, @intFromFloat(num)));
                    start += 1;
                    beginningOfLine = false;
                }
            },
            else => {},
        }

        if (beginningOfLine and end > start + 1) {
            beginningOfLine = false;
        }
    }
}

pub fn run(self: *Interpreter) !void {
    for (self.program.items) |stmt| {
        try stmt.exec(&self.state);
    }
}
