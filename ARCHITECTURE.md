# Architecture

## Overview

The Angular-Zig compiler is a 1:1 behavioral port of the Angular TypeScript compiler
to Zig 0.16. It follows the same compilation pipeline but leverages Zig's unique
features for performance and safety.

## Compilation Pipeline

```
┌─────────────────┐
│ Template String │  e.g. "<div>{{ name }}</div>"
└────────┬────────┘
         ↓
┌─────────────────┐
│  HTML Lexer     │  Tokenize → TagOpenStart, TagName, TagOpenEnd, Text, EOF
│  (ml_parser)    │  Handles: tags, attributes, entities, comments, CDATA,
│                 │  interpolation {{}}, blocks @if/@for/@switch, @defer, @let
└────────┬────────┘
         ↓
┌─────────────────┐
│  HTML Parser    │  Build AST → Element, Text, Comment, Block, Expansion
│  (ml_parser)    │  Merges adjacent text nodes
│                 │  Handles void elements, self-closing tags
└────────┬────────┘
         ↓
┌─────────────────┐
│  R3 Transform   │  HTML AST → R3 (Ivy) AST
│  (template)     │  Classifies bindings: [prop], (event), {{expr}}, *directive
│                 │  Filters: <script>, <style>, relative <link>
│                 │  Transforms: @if → IfBlock, @for → ForLoopBlock, etc.
│                 │  Handles: ng-content, ng-template, ng-container
│                 │  @defer → DeferredBlock with triggers
└────────┬────────┘
         ↓
┌─────────────────┐
│  IR Pipeline    │  ~50 transformation phases:
│  (pipeline)     │  1. Ingest R3 nodes → IR ops
│                 │  2. Naming (generate function/variable names)
│                 │  3. Style/class extraction
│                 │  4. Binding resolution
│                 │  5. Template type checking
│                 │  6. Reification (IR → output ops)
│                 │  7. Emit (output ops → JavaScript AST)
└────────┬────────┘
         ↓
┌─────────────────┐
│  Code Generation│  JavaScript AST → JavaScript source string
│  (output)       │  Source map generation
│                 │  Constant pool emission
└────────┬────────┘
         ↓
┌─────────────────┐
│  JS Source      │  "function TestComponent_Template(rf, ctx) { ... }"
└─────────────────┘
```

## Memory Management

### Arena Allocation
All AST nodes are allocated from an `AstArena` — a wrapper around `ArenaAllocator`.
This enables:
- **Zero fragmentation** — All nodes freed in one `deinit()` call
- **Fast allocation** — Bump pointer, no free list
- **Simple ownership** — Arena owns everything, no individual frees

### Ownership Tracking
For structs that mix arena-allocated and heap-allocated data (like `Message`),
ownership flags track which fields need explicit freeing:

```zig
pub const Message = struct {
    message_string: []const u8,
    owns_message_string: bool = false,  // true if heap-allocated
    allocator: ?Allocator = null,       // null if arena-allocated
    // ...
};
```

### String Interning
`StringPool` interns strings with O(1) comparison via indices:

```zig
const ref1 = try pool.intern("ngIf");  // Returns index 0
const ref2 = try pool.intern("ngIf");  // Returns same index 0
pool.eq(ref1, ref2);  // true — just compares integers
```

## Key Modules

### Expression Parser (`expression_parser/`)
Parses Angular template expressions like `a + b | pipe:arg`.
- **Lexer**: Tokenizes into numbers, strings, identifiers, operators, regexes
- **Parser**: Builds AST with precedence climbing (assignment → conditional → logical → ...)
- **Supports**: Arrow functions, optional chaining, non-null assertions, template literals

### HTML/ML Parser (`ml_parser/`)
Tokenizes and parses HTML templates.
- **Lexer**: Handles tags, attributes, entities, comments, CDATA, blocks, @let
- **Parser**: Builds AST with proper nesting, void elements, raw text elements
- **Features**: ICU expansion forms, inline comments in tags, interpolation tracking

### i18n (`i18n/`)
Internationalization message extraction and serialization.
- **Extraction**: Finds `i18n` attributes and comment blocks
- **Serialization**: XLIFF, XLIFF2, XMB, XTB formats
- **Placeholder Registry**: Generates unique placeholder names

### R3 Transform (`template/transform.zig`)
Transforms HTML AST to Ivy (R3) AST.
- **Binding classification**: `[prop]`, `(event)`, `[(two-way)]`, `{{expr}}`, `*directive`
- **Control flow**: `@if`, `@for`, `@switch`, `@defer` → Block nodes
- **Special elements**: ng-content, ng-template, ng-container
- **Filtering**: Removes `<script>`, `<style>`, relative `<link>` from output

### IR Pipeline (`template/pipeline/`)
~50-phase transformation pipeline from R3 AST to output JavaScript.
- **Ingest**: R3 nodes → IR operations
- **Phases**: Naming, style extraction, binding resolution, type checking
- **Emit**: IR operations → JavaScript AST → source string

### Type Checking (`typecheck/`)
Generates TypeScript type-checking blocks for template type safety.

## Multi-Package Structure

```
packages/
├── compiler/         — Core library (this package)
├── compiler-cli/     — CLI tool (ngc-zig)
└── compiler-node/    — NodeJS NAPI addon
```

Future packages:
- `packages/core/` — Angular core types
- `packages/common/` — Common directives/pipes
- `packages/platform-browser/` — Browser rendering

## Design Principles

1. **1:1 parity with TypeScript** — Same behavior, same error messages
2. **Zero-cost abstractions** — comptime dispatch, no runtime overhead
3. **Explicit ownership** — Every allocation tracked and freed
4. **Test everything** — 3,201 tests with real assertions, 0 leaks
