/// Compiler CLI — entry point for command-line tool
///
/// This package will provide a CLI that invokes the Angular compiler
/// from the command line, similar to `ngc` in the TypeScript ecosystem.
///
/// Future features:
///   - Compile Angular components from .ts files
///   - Extract i18n messages
///   - Generate TypeScript declarations
///   - Watch mode for incremental compilation
///
/// Currently a placeholder — will be implemented when the compiler
/// is ready for standalone use.
const std = @import("std");

pub fn main() !void {
    std.debug.print("angular-compiler-cli: not yet implemented\n", .{});
}
