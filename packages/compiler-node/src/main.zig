/// Compiler NodeJS Addon — NAPI binding for NodeJS
///
/// This package will provide a NodeJS addon (.node file) that exposes
/// the Angular compiler to JavaScript/TypeScript code, allowing:
///   - `require('angular-compiler')` from NodeJS
///   - Integration with Angular CLI (ng build, ng serve)
///   - Webpack/Vite plugins
///
/// Build options:
///   - NAPI (native addon) — fastest, requires NodeJS headers
///   - WASM — portable, runs in browser and NodeJS
///
/// Currently a placeholder.
const std = @import("std");

pub fn main() !void {
    std.debug.print("angular-compiler-node: not yet implemented\n", .{});
}
