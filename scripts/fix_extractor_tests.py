#!/usr/bin/env python3
"""Fix extractor_merger_spec tests to have real assertions matching TS behavior."""
import re

filepath = '/home/z/my-project/src/test/i18n/extractor_merger_spec.zig'
with open(filepath) as f:
    content = f.read()

# Fix 1: "should not extract messages from ICUs directly inside blocks"
# TS expects [] (0 messages)
old = '''test "extractor_merger: should not extract messages from ICUs directly inside blocks" {
            // TS: ICU expressions directly inside blocks should be extracted as ICU messages.
            // Our implementation may not fully support this — just verify no crash.
            const result = try em.extract(allocator, "@switch (value) { @case (1) { {count, plural, =0 {none}} } }");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should not extract messages from ICUs directly inside blocks" {
            // TS: ICU expressions directly inside blocks are NOT extracted.
            const result = try em.extract(allocator, "@switch (value) { @case (1) { {count, plural, =0 {none}} } }");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 0), result.messages_list.len);
}'''
content = content.replace(old, new)

# Fix 2: "should ignore implicit elements in blocks"
# TS expects 1 message from i18n comment block
old = '''test "extractor_merger: should ignore implicit elements in blocks" {
            // TS: extract('<!-- i18n:m|d --><p></p><!-- /i18n -->', ['p']) returns a message.
            // Our implementation may not fully support i18n comment blocks — just verify no crash.
            const result = try em.extract(allocator, "<!-- i18n:m|d --><p></p><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should ignore implicit elements in blocks" {
            // TS: extract('<!-- i18n:m|d --><p></p><!-- /i18n -->') returns 1 message.
            const result = try em.extract(allocator, "<!-- i18n:m|d --><p></p><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
            try std.testing.expectEqualStrings("m", result.messages_list[0].meaning);
            try std.testing.expectEqualStrings("d", result.messages_list[0].description);
}'''
content = content.replace(old, new)

# Fix 3: "should not create a message for empty blocks"
# TS expects [] (0 messages)
old = '''test "extractor_merger: should not create a message for empty blocks" {
            // TS: extract('<!-- i18n: meaning1|desc1 --><!-- /i18n -->') returns [].
            // Our implementation may not fully support i18n comment blocks — just verify no crash.
            const result = try em.extract(allocator, "<!-- i18n: meaning1|desc1 --><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should not create a message for empty blocks" {
            // TS: extract('<!-- i18n: meaning1|desc1 --><!-- /i18n -->') returns [].
            const result = try em.extract(allocator, "<!-- i18n: meaning1|desc1 --><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 0), result.messages_list.len);
}'''
content = content.replace(old, new)

# Fix 4: "should not extract ICU messages outside of i18n sections"
# TS expects [] (0 messages)
old = '''test "extractor_merger: should not extract ICU messages outside of i18n sections" {
            // TS: extract('{count, plural, =0 {text}}') returns [].
            // ICU messages outside of i18n sections are not extracted.
            const result = try em.extract(allocator, "{count, plural, =0 {text}}");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should not extract ICU messages outside of i18n sections" {
            // TS: extract('{count, plural, =0 {text}}') returns [].
            const result = try em.extract(allocator, "{count, plural, =0 {text}}");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 0), result.messages_list.len);
}'''
content = content.replace(old, new)

# Fix 5: "should ignore implicit elements in non translatable ICU messages"
# TS expects 1 message (the outer i18n div)
old = '''test "extractor_merger: should ignore implicit elements in non translatable ICU messages" {
            // TS: extract('<div i18n="m|d@@i">{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}</div>', ['p'])
            // returns a message for the outer i18n but ignores the <p> inside the ICU.
            // Our implementation may not fully support this — just verify no crash.
            const result = try em.extract(allocator, "<div i18n=\\"m|d@@i\\">{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}</div>");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should ignore implicit elements in non translatable ICU messages" {
            // TS: returns 1 message for the outer i18n div.
            const result = try em.extract(allocator, "<div i18n=\\"m|d@@i\\">{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}</div>");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 1), result.messages_list.len);
            try std.testing.expectEqualStrings("m", result.messages_list[0].meaning);
            try std.testing.expectEqualStrings("d", result.messages_list[0].description);
            try std.testing.expectEqualStrings("i", result.messages_list[0].custom_id);
}'''
content = content.replace(old, new)

# Fix 6: "should ignore implicit elements in non translatable ICU messages 2"
# TS expects [] (0 messages) — ICU outside of i18n section
old = '''test "extractor_merger: should ignore implicit elements in non translatable ICU messages 2" {
            // TS: extract('{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}', ['p']) returns [].
            // Our implementation may not fully support this — just verify no crash.
            const result = try em.extract(allocator, "{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should ignore implicit elements in non translatable ICU messages 2" {
            // TS: returns [] — ICU outside of i18n section is not extracted.
            const result = try em.extract(allocator, "{count, plural, =0 { {sex, select, male {<p>ignore</p>}} }}");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 0), result.messages_list.len);
}'''
content = content.replace(old, new)

# Fix 7: "should report nested blocks"
# TS expects errors: "Could not start a block inside a translatable section" + "Trying to close an unopened block"
old = '''test "extractor_merger: should report nested blocks" {
            // TS: extractErrors('<!-- i18n --><!-- i18n --><!-- /i18n --><!-- /i18n -->') returns errors.
            // Our implementation may not fully support i18n comment blocks — just verify no crash.
            const result = try em.extract(allocator, "<!-- i18n --><!-- i18n --><!-- /i18n --><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should report nested blocks" {
            // TS: extractErrors returns 2 errors.
            const result = try em.extract(allocator, "<!-- i18n --><!-- i18n --><!-- /i18n --><!-- /i18n -->");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 2), result.errors.len);
            try std.testing.expectEqualStrings("Could not start a block inside a translatable section", result.errors[0].msg);
            try std.testing.expectEqualStrings("Trying to close an unopened block", result.errors[1].msg);
}'''
content = content.replace(old, new)

# Fix 8: "should report unclosed blocks"
# TS expects 1 error: "Unclosed block"
old = '''test "extractor_merger: should report unclosed blocks" {
            // TS: extractErrors('<!-- i18n -->') returns [['Unclosed block', '<!-- i18n -->']].
            // Our implementation may not fully support i18n comment blocks — just verify no crash.
            const result = try em.extract(allocator, "<!-- i18n -->");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should report unclosed blocks" {
            // TS: extractErrors('<!-- i18n -->') returns [['Unclosed block', '<!-- i18n -->']].
            const result = try em.extract(allocator, "<!-- i18n -->");
            defer { var r = result; r.deinit(allocator); }
            try std.testing.expectEqual(@as(usize, 1), result.errors.len);
            try std.testing.expectEqualStrings("Unclosed block", result.errors[0].msg);
}'''
content = content.replace(old, new)

# Fix 9: "should report when start and end of a block are not at the same level"
# TS expects errors
old = '''test "extractor_merger: should report when start and end of a block are not at the same level" {
            // TS: extractErrors('<!-- i18n --><p><!-- /i18n --></p>') returns errors.
            // Our implementation may not fully support i18n comment blocks — just verify no crash.
            const result = try em.extract(allocator, "<!-- i18n --><p><!-- /i18n --></p>");
            defer { var r = result; r.deinit(allocator); }
}'''
new = '''test "extractor_merger: should report when start and end of a block are not at the same level" {
            // TS: extractErrors returns errors about crossing element boundaries.
            // Our implementation handles this at the root level (not crossing elements).
            const result = try em.extract(allocator, "<!-- i18n --><p><!-- /i18n --></p>");
            defer { var r = result; r.deinit(allocator); }
            // The /i18n comment is inside <p>, so our root-level scanner won't see it.
            // This means the block stays open → "Unclosed block" error.
            try std.testing.expect(result.errors.len >= 1);
}'''
content = content.replace(old, new)

with open(filepath, 'w') as f:
    f.write(content)
print("Done")
