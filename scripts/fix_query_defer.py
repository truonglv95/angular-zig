#!/usr/bin/env python3
"""Replace query cleanup defer blocks with deinit call."""
import re

filepath = '/home/z/my-project/src/render3/view/query_generation.zig'
with open(filepath) as f:
    content = f.read()

# Pattern: defer {
#     allocator.free(query.nodes);
#     if (query.source.len > 0) allocator.free(query.source);
# }
old = '''defer {
        allocator.free(query.nodes);
        if (query.source.len > 0) allocator.free(query.source);
    }'''
new = '''defer { var q = query; q.deinit(allocator); }'''

count = content.count(old)
content = content.replace(old, new)

with open(filepath, 'w') as f:
    f.write(content)
print(f"Replaced {count} occurrences")
