/// R3 Content Blocks — Build R3 ContentBlock nodes from HTML Block nodes
///
/// Port of: compiler/src/render3/render3/.ts (142 LoC)
const std = @import("std");

/// ContentBlock — a block of content (e.g. from @if/@for blocks in ng-content).
pub const ContentBlock = struct {
    kind: []const u8,
    parameters: []const []const u8,
    children: []const u8 = "",
};

/// Convert HTML Block nodes to R3 ContentBlock nodes.
pub fn buildContentBlocks(allocator: std.mem.Allocator, blocks: []const []const u8) ![]const ContentBlock {
    _ = allocator;
    _ = blocks;
    return &.{}; // TODO: implement
}
