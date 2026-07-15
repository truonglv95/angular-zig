#!/usr/bin/env python3
"""
Fill in the 13 skipped ml_lexer tests with real TS test inputs.
"""
import re

filepath = '/home/z/my-project/src/test/ml_parser/lexer_spec.zig'
with open(filepath) as f:
    content = f.read()

# Map of test name -> new body lines (list of strings to insert between { and })
replacements = {
    'lexer: should report unescaped ': [
        '    try expectLexerErrorsWithICU(std.testing.allocator, "<p>before { after</p>", 1);',
    ],
    'lexer: should report an error on an invalid hex sequence': [
        '    try expectLexerErrorsEscapedString(std.testing.allocator, "\\\\xGG", 1);',
        '    try expectLexerErrorsEscapedString(std.testing.allocator, "abc \\\\x xyz", 1);',
        '    try expectLexerErrorsEscapedString(std.testing.allocator, "abc\\\\x", 1);',
    ],
    'lexer: should error on an invalid fixed length Unicode sequence': [
        '    try expectLexerErrorsEscapedString(std.testing.allocator, "\\\\uGGGG", 1);',
    ],
    'lexer: should error on an invalid variable length Unicode sequence': [
        '    try expectLexerErrorsEscapedString(std.testing.allocator, "\\\\u{GG}", 1);',
    ],
    'lexer: should handle @let declaration with invalid syntax in the value': [
        '    try expectLexerErrors(std.testing.allocator, "@let foo = \\";", 1);',
        '    try expectTokens(std.testing.allocator, "@let foo = {a: 1,;", 1);',
        '    try expectTokens(std.testing.allocator, "@let foo = [1, ;", 1);',
        '    try expectTokens(std.testing.allocator, "@let foo = fn(;", 1);',
    ],
    'lexer: should report missing closing single quote': [
        '    try expectLexerErrors(std.testing.allocator, "<t a=\'b>", 1);',
    ],
    'lexer: should report missing closing double quote': [
        "    try expectLexerErrors(std.testing.allocator, '<t a=\"b>', 1);",
    ],
    'lexer: should report missing name after </': [
        '    try expectLexerErrors(std.testing.allocator, "</", 1);',
    ],
    'lexer: should report missing >': [
        '    try expectLexerErrors(std.testing.allocator, "</test", 1);',
    ],
    'lexer: should report malformed/unknown entities': [
        '    try expectLexerErrors(std.testing.allocator, "&tbo;", 1);',
        '    try expectLexerErrors(std.testing.allocator, "&#3sdf;", 1);',
        '    try expectLexerErrors(std.testing.allocator, "&#xasdf;", 1);',
        '    try expectLexerErrors(std.testing.allocator, "&#xABC", 1);',
    ],
    'lexer: should ignore invalid start tag in interpolation': [
        '    try expectTokensWithICU(std.testing.allocator, "<code>{{\'<={\'}}</code>", 1);',
    ],
    'lexer: should report invalid quotes in a parameter': [
        "    try expectLexerErrors(std.testing.allocator, '@if (a === \") {hello}', 1);",
        "    try expectLexerErrors(std.testing.allocator, '@if (a === \"hi\\') {hello}', 1);",
    ],
    'lexer: should report unclosed object literal inside a parameter': [
        '    try expectTokens(std.testing.allocator, "@if ({invalid: true) hello}", 1);',
    ],
}

lines = content.split('\n')
output = []
i = 0
replaced = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r'^test "([^"]+)" \{$', line)
    if m:
        test_name = m.group(1)
        if test_name in replacements:
            # Find the end of the test function (matching closing brace)
            depth = 1
            j = i + 1
            while j < len(lines) and depth > 0:
                if lines[j].endswith('{') and not lines[j].strip().startswith('//'):
                    depth += 1
                elif lines[j] == '}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            # Emit the test with new body
            output.append(line)  # test "name" {
            for body_line in replacements[test_name]:
                output.append(body_line)
            output.append('}')
            replaced += 1
            i = j + 1
            continue
    output.append(line)
    i += 1

with open(filepath, 'w') as f:
    f.write('\n'.join(output))

print(f"Replaced {replaced} tests")
