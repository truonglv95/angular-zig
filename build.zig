const std = @import("std");

/// Workspace root build file.
///
/// This is the entry point for the Angular-Zig monorepo.
/// It delegates to individual package build files:
///   - packages/compiler     — Core compiler library + tests
///   - packages/compiler-cli — CLI tool (future)
///   - packages/compiler-node — NodeJS addon (future)
///
/// Usage:
///   zig build              — Build the compiler library
///   zig build test         — Run all tests
///   zig build examples     — Build example binaries
///   zig build bench        — Run benchmarks
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── Compiler Package (core library) ──────────────────────
    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "angular-compiler",
        .root_module = compiler_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // ─── Tests ─────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("packages/compiler/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);

    // ─── Examples ──────────────────────────────────────────────
    const example_step = b.step("examples", "Build example binaries");

    const example_compile = b.addExecutable(.{
        .name = "example-compile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/compiler/examples/compile.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    example_compile.root_module.addImport("angular-compiler", lib.root_module);
    example_step.dependOn(&example_compile.step);

    // ─── Benchmark ─────────────────────────────────────────────
    const bench_compile = b.addExecutable(.{
        .name = "bench-compile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/compiler/examples/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_compile.root_module.addImport("angular-compiler", lib.root_module);
    const run_bench = b.addRunArtifact(bench_compile);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);

    // ─── CLI (placeholder) ─────────────────────────────────────
    const cli = b.addExecutable(.{
        .name = "ngc-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/compiler-cli/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(cli);

    // ─── NodeJS Addon (placeholder) ────────────────────────────
    const node_addon = b.addExecutable(.{
        .name = "angular-compiler-node",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/compiler-node/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(node_addon);
}
