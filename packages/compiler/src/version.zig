/// Version — Compiler version string
///
/// Port of: compiler/src/version.ts (17 LoC) — 100% match
const std = @import("std");

/// Version string matching Angular's version format.
pub const VERSION = "19.0.0-zig";

/// Full version string for display.
pub const FULL_VERSION = "angular-compiler-zig 19.0.0 (Zig 0.16)";

/// Major version number.
pub const MAJOR: u32 = 19;

/// Minor version number.
pub const MINOR: u32 = 0;

/// Patch version number.
pub const PATCH: u32 = 0;

/// Get the version as a semver string.
pub fn getVersion() []const u8 {
    return VERSION;
}

/// Check if this version is compatible with a given version string.
pub fn isCompatible(version: []const u8) bool {
    // Check major version matches
    if (version.len < 2) return false;
    return std.mem.startsWith(u8, version, "19") or
        std.mem.startsWith(u8, version, "18") or
        std.mem.startsWith(u8, version, "17");
}
