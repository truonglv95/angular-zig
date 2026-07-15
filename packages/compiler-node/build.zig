const std = @import("std");

/// Build file for the `compiler-node` package.
/// Produces a NodeJS native addon (.node) or WASM module.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── NodeJS Addon (placeholder) ────────────────────────────
    // When NAPI bindings are implemented, this will produce a .node file.
    // For now, just a placeholder executable.
    const addon = b.addExecutable(.{
        .name = "angular-compiler-node",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(addon);
}
