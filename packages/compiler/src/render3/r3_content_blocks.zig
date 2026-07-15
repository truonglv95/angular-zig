/// R3 Content Blocks — Build ContentBlock nodes from HTML Block nodes
const std = @import("std");

pub const ContentBlockKind = enum(u8) { If, For, Switch, Defer, Let, NgContent };

pub const ContentBlock = struct {
    kind: ContentBlockKind,
    name: []const u8,
    parameters: []const ContentBlockParameter = &.{},
};
pub const ContentBlockParameter = struct { expression: []const u8 };

pub fn buildContentBlocks(allocator: std.mem.Allocator, names: []const []const u8) ![]const ContentBlock {
    var blocks = std.ArrayList(ContentBlock).init(allocator);
    for (names) |name| {
        const kind: ContentBlockKind = if (std.mem.eql(u8, name, "if")) .If else if (std.mem.eql(u8, name, "for")) .For else if (std.mem.eql(u8, name, "switch")) .Switch else if (std.mem.eql(u8, name, "defer")) .Defer else if (std.mem.eql(u8, name, "let")) .Let else .NgContent;
        try blocks.append(.{ .kind = kind, .name = name });
    }
    return blocks.toOwnedSlice();
}

pub fn isContentBlock(name: []const u8) bool {
    return std.mem.eql(u8, name, "if") or std.mem.eql(u8, name, "for") or std.mem.eql(u8, name, "switch") or std.mem.eql(u8, name, "defer") or std.mem.eql(u8, name, "let");
}
