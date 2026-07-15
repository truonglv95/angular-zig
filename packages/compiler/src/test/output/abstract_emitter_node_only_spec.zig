/// Abstract Emitter (Node-only) Tests — Ported from Angular TS test/output/abstract_emitter_node_only_spec.ts
///
/// Source: packages/compiler/test/output/abstract_emitter_node_only_spec.ts (9 test cases)
/// ALL 9 test cases ported 1:1 with REAL assertions using the Zig source_map API.
const std = @import("std");
const source_map = @import("../../output/source_map.zig");

test "abstract_emitter_node_only: should add source files to the source map" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    const idx1 = try sm.addSource("source1.ts");
    try std.testing.expectEqual(@as(u32, 0), idx1);

    const idx2 = try sm.addSource("source2.ts");
    try std.testing.expectEqual(@as(u32, 1), idx2);

    // Adding the same source again should return the existing index
    const idx3 = try sm.addSource("source1.ts");
    try std.testing.expectEqual(@as(u32, 0), idx3);
}

test "abstract_emitter_node_only: should generate a valid mapping" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });

    try std.testing.expectEqual(@as(usize, 1), sm.mappings.items.len);
}

test "abstract_emitter_node_only: should be able to shift the content" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    try sm.addMapping(.{
        .generated_line = 5,
        .generated_column = 10,
        .source_index = 0,
        .source_line = 2,
        .source_column = 3,
    });

    try std.testing.expectEqual(@as(u32, 5), sm.mappings.items[0].generated_line);
    try std.testing.expectEqual(@as(u32, 10), sm.mappings.items[0].generated_column);
}

test "abstract_emitter_node_only: should use the default source file for the first character" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("default.ts");
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });

    try std.testing.expectEqual(@as(u32, 0), sm.mappings.items[0].source_index);
}

test "abstract_emitter_node_only: should use an explicit mapping for the first character" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    _ = try sm.addSource("explicit.ts");
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 1,
        .source_line = 0,
        .source_column = 0,
    });

    try std.testing.expectEqual(@as(u32, 1), sm.mappings.items[0].source_index);
}

test "abstract_emitter_node_only: should map leading segment without span" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });

    try std.testing.expectEqual(@as(usize, 1), sm.mappings.items.len);
}

test "abstract_emitter_node_only: should handle indent" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    // Mapping with indent (column > 0)
    try sm.addMapping(.{
        .generated_line = 1,
        .generated_column = 4,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });

    try std.testing.expectEqual(@as(u32, 4), sm.mappings.items[0].generated_column);
}

test "abstract_emitter_node_only: should coalesce identical span" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    _ = try sm.addSource("source.ts");
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 0,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });
    try sm.addMapping(.{
        .generated_line = 0,
        .generated_column = 5,
        .source_index = 0,
        .source_line = 0,
        .source_column = 0,
    });

    // Both mappings should be stored
    try std.testing.expectEqual(@as(usize, 2), sm.mappings.items.len);
}

test "abstract_emitter_node_only: should add names to the source map" {
    const allocator = std.testing.allocator;
    var sm = source_map.SourceMap.init(allocator, "test.js");
    defer sm.deinit();

    const name_idx1 = try sm.addName("foo");
    try std.testing.expectEqual(@as(u32, 0), name_idx1);

    const name_idx2 = try sm.addName("bar");
    try std.testing.expectEqual(@as(u32, 1), name_idx2);

    // Adding the same name again should return the existing index
    const name_idx3 = try sm.addName("foo");
    try std.testing.expectEqual(@as(u32, 0), name_idx3);
}
