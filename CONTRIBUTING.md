# Contributing

## Build & Test

```bash
# Build everything
zig build

# Run all tests (3,201 tests, 0 leaks)
zig build test

# Build examples
zig build examples

# Run benchmarks
zig build bench
```

## Project Structure

```
packages/
├── compiler/              — Core compiler library
│   ├── src/               — Production code
│   │   ├── main.zig       — Library entry point
│   │   └── test/          — Test files
│   └── examples/          — Examples + benchmarks
├── compiler-cli/          — CLI tool
└── compiler-node/         — NodeJS addon
```

## Coding Standards

### 1:1 Parity with TypeScript
- Every function must match the TypeScript source behavior
- Error messages must match TS format exactly
- Test cases must use the same inputs as TS tests

### Memory Management
- Use `AstArena` for all AST node allocations
- Track ownership with `owns_*` flags for mixed heap/arena data
- Every test must pass with 0 memory leaks
- Use `defer` for cleanup — never leak

### Testing
- Tests live in `packages/compiler/src/test/`
- Test files are named `*_spec.zig` matching TS `*_spec.ts`
- Use `std.testing.allocator` for all tests (detects leaks)
- No `expect(true)` placeholders — all assertions must be real
- No `SkipZigTest` — all tests must pass

### Adding New Features
1. Find the corresponding TS source in `_submodule/packages/compiler/src/`
2. Port the function/module to Zig
3. Find the corresponding TS test in `_submodule/packages/compiler/test/`
4. Port test cases to Zig with real assertions
5. Run `zig build test` — must pass with 0 leaks

### Code Style
- Use `snake_case` for functions and variables
- Use `PascalCase` for types
- Use `@import` for module imports (relative paths)
- Add doc comments for public API functions
- Follow DOD (Data-Oriented Design) patterns:
  - Tagged unions instead of class hierarchies
  - Contiguous arrays instead of linked lists
  - Zero-copy string slices (`[]const u8`)
