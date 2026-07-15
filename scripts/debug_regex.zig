const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const src = "foo()! / 2";
    var l = lexer.Lexer.init(allocator, src);
    defer l.deinit();
    const tokens = try l.tokenize();
    for (tokens, 0..) |t, i| {
        std.debug.print("[{}] type={} str='{s}'\n", .{i, @tagName(t.type), t.slice(src)});
    }
}
