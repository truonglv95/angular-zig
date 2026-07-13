/// R3 Template Transform — Convert HTML AST to R3 AST
///
/// Port of: compiler/src/render3/render3/.ts (1296 LoC)
const std = @import("std");

/// Transform HTML AST to R3 AST.
/// This is the main entry point for template → R3 conversion.
/// The actual implementation lives in template/transform.zig — this file
/// is the Angular-matching entry point that delegates to it.
const template_transform = @import("../template/transform.zig");

pub const transformHtmlToR3 = template_transform.transformHtmlToR3;
