const std = @import("std");

/// Build file for the `compiler` package.
/// Exports the `angular-compiler` module for use by other packages.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── Library Module ────────────────────────────────────────
    const lib = b.addLibrary(.{
        .name = "angular-compiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    b.installArtifact(lib);

    // ─── Tests ─────────────────────────────────────────────────
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run compiler tests");
    test_step.dependOn(&run_lib_tests.step);

    // ─── Examples ──────────────────────────────────────────────
    const example_step = b.step("examples", "Build example binaries");

    const example_compile = b.addExecutable(.{
        .name = "example-compile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/compile.zig"),
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
            .root_source_file = b.path("examples/bench.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_compile.root_module.addImport("angular-compiler", lib.root_module);
    const run_bench = b.addRunArtifact(bench_compile);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
