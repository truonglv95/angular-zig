# Angular Compiler — Zig Port

A high-performance port of the Angular compiler from TypeScript to Zig 0.16.

## Overview

This project ports the Angular compiler (originally ~64K lines of TypeScript) to Zig,
leveraging Zig's compile-time features, zero-copy strings, and arena allocation for
maximum performance while maintaining 1:1 behavioral parity with the original.

### Stats

| Metric | Value |
|--------|-------|
| Source files | 296 `.zig` files |
| Source lines | ~70,700 lines (production) |
| Test lines | ~13,400 lines |
| Test cases | 3,201 tests |
| Test pass rate | 100% (0 failures, 0 skips) |
| Memory leaks | 0 |
| Original TS lines | ~63,800 lines |

## Project Structure

```
packages/
├── compiler/                  — Core compiler library
│   ├── build.zig              — Package build (library, tests, examples, bench)
│   ├── src/
│   │   ├── main.zig           — Library entry point (public API)
│   │   ├── compiler.zig       — Compiler orchestration pipeline
│   │   ├── arena.zig          — Arena allocator for AST nodes
│   │   ├── chars.zig          — Character classification helpers
│   │   ├── source_span.zig    — Source span / location tracking
│   │   ├── interned.zig       — String interning pool
│   │   ├── config.zig         — Compiler configuration
│   │   ├── core.zig           — Core types (FactoryTarget, etc.)
│   │   ├── directive_matching.zig — CSS selector matching
│   │   ├── shadow_css.zig     — Shadow DOM CSS encapsulation
│   │   ├── constant_pool.zig  — Constant pool for compiled output
│   │   │
│   │   ├── expression_parser/ — Angular expression parser
│   │   │   ├── ast.zig        — Expression AST types
│   │   │   ├── lexer.zig      — Expression tokenizer
│   │   │   ├── parser.zig     — Expression parser (binding/action)
│   │   │   └── serializer.zig — AST serializer
│   │   │
│   │   ├── ml_parser/         — HTML/ML parser
│   │   │   ├── ast.zig        — HTML AST types
│   │   │   ├── lexer.zig      — HTML tokenizer
│   │   │   ├── parser.zig     — HTML parser
│   │   │   ├── tags.zig       — Tag definitions
│   │   │   ├── entities.zig   — HTML entity table
│   │   │   └── html_whitespaces.zig
│   │   │
│   │   ├── i18n/              — Internationalization
│   │   │   ├── i18n_ast.zig   — i18n AST types
│   │   │   ├── i18n_parser.zig — i18n message parser
│   │   │   ├── extractor_merger.zig — Message extraction
│   │   │   ├── digest.zig     — Message digest computation
│   │   │   ├── translation_bundle.zig
│   │   │   ├── message_bundle.zig
│   │   │   ├── i18n_html_parser.zig
│   │   │   └── serializers/   — XLIFF, XMB, XTB serializers
│   │   │
│   │   ├── render3/           — Ivy (R3) template compiler
│   │   │   ├── r3_ast.zig     — R3 AST types
│   │   │   ├── r3_identifiers.zig
│   │   │   ├── view/          — View compilation
│   │   │   │   ├── t2_binder.zig
│   │   │   │   ├── query_generation.zig
│   │   │   │   └── i18n/      — View-level i18n
│   │   │   └── partial/       — Partial compilation
│   │   │
│   │   ├── template/          — Template transformation
│   │   │   ├── transform.zig  — HTML → R3 AST transform
│   │   │   └── pipeline/      — IR pipeline (~50 phases)
│   │   │       ├── ir/        — Intermediate representation
│   │   │       └── src/       — Pipeline phases
│   │   │
│   │   ├── template_parser/   — Template preparsing
│   │   ├── schema/            — DOM element schema
│   │   ├── output/            — Code generation
│   │   ├── typecheck/         — Type checking block
│   │   └── test/              — Test files (same module root)
│   │
│   └── examples/              — Example binaries + benchmarks
│       ├── compile.zig        — Compilation example
│       └── bench.zig          — Performance benchmark
│
├── compiler-cli/              — CLI tool (placeholder)
│   ├── build.zig
│   └── src/main.zig           — `ngc-zig` CLI entry point
│
└── compiler-node/             — NodeJS NAPI addon (placeholder)
    ├── build.zig
    └── src/main.zig           — NodeJS addon entry point

build.zig                      — Workspace root (aggregates all packages)
_submodule/                    — Angular TS source (reference)
```

## Build Commands

```bash
# Build everything (library + CLI + NodeJS addon)
zig build

# Run all tests
zig build test

# Build examples
zig build examples

# Run benchmarks
zig build bench
```

## Compilation Pipeline

```
Template string
    ↓
HTML Lexer (tokenize)
    ↓
HTML Parser (AST)
    ↓
R3 Transform (Ivy AST)
    ↓
IR Ingest (~50 phases)
    ↓
IR Emit (output AST)
    ↓
JavaScript source code
```

## Key Design Decisions

1. **DOD (Data-Oriented Design)** — Tagged unions instead of class hierarchies
2. **Arena allocation** — Single bulk free for all AST nodes
3. **Zero-copy strings** — `[]const u8` slices into source
4. **String interning** — O(1) string comparison via indices
5. **comptime visitors** — Type-safe AST visitor pattern
6. **Ownership tracking** — `owns_*` flags on Message structs for precise cleanup

## Test Coverage

All 53 TypeScript test spec files have corresponding Zig test files:

| Module | TS tests | Zig tests |
|--------|----------|-----------|
| expression_parser | 343 | 394 |
| ml_parser | 425 | 584 |
| i18n | 143 | 148 |
| render3 | 380 | 213 |
| shadow_css | 118 | 123 |
| selector | 35 | 34 |
| schema | 33 | 33 |
| output | 27 | 33 |
| other | 20 | 22 |

## License

MIT — Same as Angular.
