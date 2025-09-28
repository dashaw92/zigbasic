const interp = @import("interpreter.zig");
const state = @import("state.zig");
const lexer = @import("lexer.zig");

pub const Interpreter = interp;
pub const MemoryExtension = state.MemoryExtension;
pub const Value = state.Value;
