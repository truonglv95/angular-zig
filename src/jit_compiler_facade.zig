/// JIT Compiler Facade — Just-In-Time compilation entry point
///
/// Port of: compiler/src/jit_compiler_facade.ts
const std = @import("std");

/// Facade for JIT (Just-In-Time) template compilation.
/// In AOT mode, this is not used — the compiler runs at build time.
pub const JitCompilerFacade = struct {};
