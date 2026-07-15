const std = @import("std");

/// Build file for the `compiler-cli` package.
/// Produces a CLI binary that depends on the `compiler` package.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ─── CLI Executable ────────────────────────────────────────
    const cli = b.addExecutable(.{
        .name = "ngc-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Import the compiler package (when ready)
    // const compiler_dep = b.dependency("compiler", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // cli.root_module.addImport("angular-compiler", compiler_dep.module("angular-compiler"));

    b.installArtifact(cli);
}
