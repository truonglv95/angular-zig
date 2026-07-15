# Changelog

All notable changes to the Angular-Zig compiler project.

## [Unreleased]

### Monorepo Restructure
- Restructured project into multi-package monorepo workspace
- `packages/compiler/` — Core compiler library (296 .zig files, ~70K lines)
- `packages/compiler-cli/` — CLI tool placeholder (`ngc-zig`)
- `packages/compiler-node/` — NodeJS NAPI addon placeholder
- Root `build.zig` aggregates all packages
- All 3,201 tests pass with 0 memory leaks

### API Implementations
- **@defer block handler**: Parse triggers (on hover/interaction/viewport, when, idle, timer)
- **Script/style filtering**: `<script>`, `<style>`, relative `<link>` filtered from R3 AST
- **ICU expansion forms**: `tokenize_icu` enabled in extractor, `parseExpansionForm` in parser
- **i18n comment blocks**: `<!-- i18n:m|d -->...<!-- /i18n -->` support with error reporting
- **Event property validation**: `on*` prefix check in `validateProperty`/`validateAttribute`
- **Unescaped `$` error**: `error.UnescapedDollar` for invalid attribute selectors
- **XMB load()**: Returns `error.Unsupported` (matching TS throw behavior)
- **XML DOCTYPE parsing**: XTB serializer handles `<!DOCTYPE ... ]>` declarations

### Test Improvements
- Filled 141 empty `""` test inputs in `lexer_spec.zig` with real TS HTML strings
- Ported 64 missing `r3_template_transform_spec` test cases
- Ported 7 `i18n_ast_spec` test cases for message serialization
- Ported 4 `whitespace_sensitivity_spec` test cases with real assertions
- Ported 2 missing `keyframes_spec` test cases
- Replaced 9 `parseI18nAttrValue` workarounds with real `em.extract()` calls
- Replaced all "verify no crash" patterns with real assertions
- Implemented `expectErrorToken` and `expectRegExpBodyToken` with token checks
- `checkTemplateBindings` now asserts 0 parse errors

### Memory Leak Fixes (1085 → 0)
- **typecheck/ops/scope**: Free memoized result strings in op_queue
- **i18n/i18n_ast**: owns_message_string/owns_sources/owns_id/owns_nodes flags + placeholder_registry ownership transfer
- **i18n/extractor_merger**: ExtractionResult.deinit, freeHtmlNodeInputs recursive cleanup
- **i18n/i18n_parser**: Heap-allocate context, string_arena for all string/node allocations
- **i18n/index**: Free ICU case arrays in I18nExtractor.deinit
- **i18n/serializers/xtb**: LoadResult.deinit frees node arrays
- **compiler**: Free consts_name, template_fn_name, defer compiler.deinit()
- **template/pipeline/ir/emit**: Use expr_arena for all emit allocations
- **template/pipeline/ir/reify**: Use toOwnedSlice, ReifiedView.deinit frees ops
- **template/pipeline/ir/job**: Free fn_name in ViewCompilationUnit.deinit
- **render3/view/query_generation**: CompiledQuery.deinit recursive, fix left_items leak
- **render3/r3_identifiers**: Return owned keys, free all duped keys
- **expression_parser/parser**: SplitInterpolation.deinit
- **directive_matching**: Selector.deinit recursive (inner :not selectors)
- **ml_parser/ast**: ParseTreeResult.deinit frees root_nodes
- **template/pipeline/parse_extracted_styles**: freeResult helper
- **All test helpers**: Proper defer deinit across 15+ spec files

### Bug Fixes
- Fixed `isRegexStart()` for `a!/regex/` (non-null assertion detection)
- Emit single-character punctuation as `Character` tokens (matching TS)
- Fixed arrow function body to use `parseAssignment` with `is_action=true`
- Fixed block body detection: `() => {}` reports "Multi-line arrow functions are not supported"
- Fixed `scanTagEnd` to not emit `TagOpenEnd` for incomplete tags
- Fixed `scanAttributes` to break on `<` (incomplete tag like `<a <span>`)
- Fixed `parseElement` to skip children when tag has no closing `>`
- Added `mergeAdjacentTextNodes` to parser (direct port of TS `mergeTextTokens`)
- Fixed `Scope.deinit` to not double-free stack-allocated child scopes

### Phase 9 — Test Suite Port (3,135 → 3,201 tests)
- Ported all 36 skipped tests to passing
- 13 ml_lexer tests: escapedString mode, entity validation, missing token detection
- 3 expression_lexer tests: isRegexStart fix for non-null assertions
- 1 html_whitespaces test: block whitespace removal
- 1 binding_spec test: Scope child lifetime
- 2 r3_template_transform tests: incomplete tags, named entities
- 7 parser_spec tests: arrow fn edge cases, quotes in comments, parenthesis spans
- 10 extractor_merger tests: i18n comment blocks, error reporting
