#!/usr/bin/env python3
"""Fix extractor_merger tests that use parseI18nAttrValue as workaround."""
import re

filepath = '/home/z/my-project/src/test/i18n/extractor_merger_spec.zig'
with open(filepath) as f:
    content = f.read()

# Fix "should extract from elements inside blocks"
old = '''test "extractor_merger: should extract from elements inside blocks" {
    // Verify i18n attr parsing for @if blocks
    const info = em.parseI18nAttrValue("m|d");
    try std.testing.expectEqualStrings("m", info.meaning);
}'''
new = '''test "extractor_merger: should extract from elements inside blocks" {
    // TS: extract from @switch/@case blocks with i18n elements.
    const result = try em.extract(allocator, "@switch (value) { @case (1) { <div i18n=\\"a|b|c\\">one <span>nested</span></div> } @case (2) { <strong i18n=\\"d|e|f\\">two <span>nested</span></strong> } @default { <strong i18n=\\"g|h|i\\">default <span>nested</span></strong> } }");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 3), result.messages_list.len);
    try std.testing.expectEqualStrings("a", result.messages_list[0].meaning);
    try std.testing.expectEqualStrings("d", result.messages_list[1].meaning);
    try std.testing.expectEqualStrings("g", result.messages_list[2].meaning);
}'''
content = content.replace(old, new)

# Fix "should extract ICUs from elements inside blocks"
old = '''test "extractor_merger: should extract ICUs from elements inside blocks" {
    const info = em.parseI18nAttrValue("m|d");
    try std.testing.expectEqualStrings("m", info.meaning);
}'''
new = '''test "extractor_merger: should extract ICUs from elements inside blocks" {
    // TS: ICU expressions inside i18n elements inside blocks are extracted.
    const result = try em.extract(allocator, "@switch (value) { @case (1) { <div i18n=\\"a|b\\">{count, plural, =0 {none}}</div> } }");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
    try std.testing.expectEqualStrings("a", result.messages_list[0].meaning);
    try std.testing.expectEqualStrings("b", result.messages_list[0].description);
}'''
content = content.replace(old, new)

# Fix "should extract from blocks"
old = '''test "extractor_merger: should extract from blocks" {
    // Verify i18n attr parsing
    const info = em.parseI18nAttrValue("m|d");
    try std.testing.expectEqualStrings("m", info.meaning);
}'''
new = '''test "extractor_merger: should extract from blocks" {
    // TS: extract from i18n comment blocks.
    const result = try em.extract(allocator, "<!-- i18n: meaning1|desc1 -->message1<!-- /i18n -->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
    try std.testing.expectEqualStrings("meaning1", result.messages_list[0].meaning);
    try std.testing.expectEqualStrings("desc1", result.messages_list[0].description);
}'''
content = content.replace(old, new)

# Fix "should extract ICU messages from translatable elements"
old = '''test "extractor_merger: should extract ICU messages from translatable elements" {
    const info = em.parseI18nAttrValue("m|d");
    try std.testing.expectEqualStrings("m", info.meaning);
}'''
new = '''test "extractor_merger: should extract ICU messages from translatable elements" {
    // TS: extract('<div i18n="m|d">{count, plural, =0 {text}}</div>') returns 1 message.
    const result = try em.extract(allocator, "<div i18n=\\"m|d\\">{count, plural, =0 {text}}</div>");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
    try std.testing.expectEqualStrings("m", result.messages_list[0].meaning);
    try std.testing.expectEqualStrings("d", result.messages_list[0].description);
}'''
content = content.replace(old, new)

# Fix "should extract ICU messages from translatable block"
old = '''test "extractor_merger: should extract ICU messages from translatable block" {
    const info = em.parseI18nAttrValue("m|d");
    try std.testing.expectEqualStrings("m", info.meaning);
}'''
new = '''test "extractor_merger: should extract ICU messages from translatable block" {
    // TS: ICU inside i18n comment block.
    const result = try em.extract(allocator, "<!-- i18n: m|d -->{count, plural, =0 {text}}<!-- /i18n -->");
    defer { var r = result; r.deinit(allocator); }
    try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
    try std.testing.expectEqualStrings("m", result.messages_list[0].meaning);
    try std.testing.expectEqualStrings("d", result.messages_list[0].description);
}'''
content = content.replace(old, new)

with open(filepath, 'w') as f:
    f.write(content)
print("Done")
