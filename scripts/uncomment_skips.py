#!/usr/bin/env python3
"""
Uncomment SkipZigTest tests in any spec file, preserving the original body.
Uses robust string-aware brace matching.
"""
import re
import sys

def uncomment_file(filepath):
    with open(filepath) as f:
        content = f.read()

    lines = content.split('\n')

    def find_test_end(start):
        depth = 1
        in_string = False
        string_char = None
        in_line_comment = False
        in_block_comment = False
        j = start + 1
        while j < len(lines):
            line = lines[j]
            k = 0
            while k < len(line):
                ch = line[k]
                if in_line_comment:
                    break
                if in_block_comment:
                    if ch == '*' and k + 1 < len(line) and line[k+1] == '/':
                        in_block_comment = False
                        k += 2
                        continue
                    k += 1
                    continue
                if in_string:
                    if ch == '\\':
                        k += 2
                        continue
                    if ch == string_char:
                        in_string = False
                    k += 1
                    continue
                if ch == '/' and k + 1 < len(line) and line[k+1] == '/':
                    in_line_comment = True
                    break
                if ch == '/' and k + 1 < len(line) and line[k+1] == '*':
                    in_block_comment = True
                    k += 2
                    continue
                if ch == '"' or ch == "'":
                    in_string = True
                    string_char = ch
                    k += 1
                    continue
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0:
                        return j
                k += 1
            j += 1
            in_line_comment = False
        return -1

    output_lines = []
    i = 0
    uncommented = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^test "([^"]+)" \{$', line)
        if m:
            end = find_test_end(i)
            if end != -1:
                body = lines[i+1:end]
                has_skip = any('return error.SkipZigTest;' in l for l in body)
                if has_skip:
                    output_lines.append(line)
                    for bl in body:
                        if 'return error.SkipZigTest;' in bl:
                            continue
                        bm = re.match(r'^(\s*)//\s?(.*)', bl)
                        if bm:
                            output_lines.append(bm.group(1) + bm.group(2))
                        else:
                            output_lines.append(bl)
                    output_lines.append('}')
                    uncommented += 1
                    i = end + 1
                    continue
        output_lines.append(line)
        i += 1

    with open(filepath, 'w') as f:
        f.write('\n'.join(output_lines))
    return uncommented

if __name__ == '__main__':
    for filepath in sys.argv[1:]:
        count = uncomment_file(filepath)
        print(f"{filepath}: Uncommented {count} tests")
