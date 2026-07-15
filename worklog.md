---
Task ID: phase9-ml-lexer-13
Agent: main
Task: Implement missing lexer APIs to pass all 13 skipped ml_lexer tests,
keeping test logic 1:1 with the TS source.

Work Log:
- Read TS source: _submodule/packages/compiler/src/ml_parser/lexer.ts
  to understand the exact error messages and behaviors expected.
- Read TS test source: _submodule/packages/compiler/test/ml_parser/lexer_spec.ts
  to extract the real test inputs for the 13 skipped tests.
- Added TokenizeOptions.escaped_string field (direct port of TS escapedString option).
- Added TokenizeOptions defaults: tokenize_blocks=true, tokenize_let=true
  (matching TS `tokenizeBlocks ?? true` and `tokenizeLet ?? true`).
- Added new HtmlTokenType variants: IncompleteBlockOpen, IncompleteLet, InElementComment.
- Added Lexer.in_interpolation field for tracking interpolation state.
- Added Lexer.owned_strings list for tracking dynamically-allocated strings.
- Added Lexer.reportErrorFmt helper for formatted error messages.
- Reordered @let check BEFORE @block check in tokenize() (matching TS source order).
- Added handleBlockEnd() for `}` -> BLOCK_CLOSE token.
- Rewrote handleBlockStart() to mark INCOMPLETE_BLOCK_OPEN when no `{` follows
  the parameters, and to handle `@default never;` special case.
- Rewrote scanBlockParameters() to track quotes (`'`, `"`, `` ` ``) and nested
  parens, reporting `Unexpected character "EOF"` for unterminated strings.
- Rewrote handleLetDeclaration() to scan values with string-aware skipping,
  reporting `Unexpected character "EOF"` for unterminated strings and emitting
  IncompleteLet token when value is malformed.
- Rewrote scanEntity() to produce TS-matching error messages:
  * `Unknown entity "<name>" - use the "&#<decimal>;" or  "&#x<hex>;" syntax`
  * `Unable to parse entity "<text>" - {decimal|hexadecimal} character
     reference entities must end with ";"`
  * `Unexpected character "EOF"` for missing semicolon at EOF
  * Properly decode numeric/named entities into their UTF-8 values.
- Rewrote scanExpansionForm() to report the unescaped-{-error message exactly
  matching TS: `Unexpected character "EOF" (Do you have an unescaped "{" ...)`.
- Fixed scanAttributeValue() to report `Unexpected character "EOF"` at EOF
  position (not value start) when closing quote is missing.
- Fixed scanTagEnd() to report `Unexpected character "EOF"` at EOF and
  `Unexpected character "<c>"` for non-EOF cases.
- Fixed handleTagStart() closing-tag branch to report `Unexpected character "EOF"`
  at EOF for missing name after `</`.
- Added scanEscapedStringText() method for escapedString mode that processes
  escape sequences (`\xGG`, `\uGGGG`, `\u{GG...}`, `\n`, `\012`, line
  continuations) and reports `Invalid hexadecimal escape sequence` for invalid
  hex/unicode escapes.
- Updated top-level tokenize() to deep-copy error messages and entity values
  so returned tokens/errors outlive the lexer.
- Filled in real TS test inputs for the 13 previously-skipped tests in
  src/test/ml_parser/lexer_spec.zig (using scripts/fill_ml_lexer_tests.py).
- Added expectLexerErrorsEscapedString and expectTokensWithICU test helpers.
- Updated tokenize entity reference/decimal/hex tests to check decoded values
  (matching TS behavior) instead of the entity source name.
- Verified all 13 ml_lexer tests now pass.

Stage Summary:
- Test count: 3099 pass / 36 skip / 2 fail (baseline)
                 -> 3112 pass / 23 skip / 0 fail (after)
- All 13 ml_lexer skips are now passing tests (0 skips in lexer_spec.zig).
- All 13 tests use REAL TS test inputs (not empty placeholders).
- All error messages match TS format 1:1.
- Pre-existing 1057 leaks unchanged (not introduced by this work).
- Remaining 23 skips are in other spec files (extractor_merger, parser_spec,
  expression_lexer, r3_template_transform, binding_spec, html_whitespaces).
- Commit: 2ef3d98
