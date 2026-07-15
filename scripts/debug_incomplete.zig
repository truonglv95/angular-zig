const std = @import("std");
const lexer = @import("../../src/ml_parser/lexer.zig");
const parser = @import("../../src/ml_parser/parser.zig");
const arena_mod = @import("../../src/arena.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const source = "<a <span></span>";
    var lex = lexer.Lexer.init(allocator, source);
    defer lex.deinit();
    const lex_result = try lex.tokenize();
    for (lex_result[0], 0..) |t, i| {
        std.debug.print("[{}] type={s} str='{s}'\n", .{i, @tagName(t.type), t.slice(source)});
    }
}
