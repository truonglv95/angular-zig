/// Namespace constants
///
/// Port of: template/pipeline/src/namespaces.ts (10 LoC)
///
/// DOD: plain string constants — zero allocation, zero indirection.
const std = @import("std");

/// Tag name prefix for SVG namespace elements (e.g., `svg:rect`).
pub const SVG_NAMESPACE = "svg";

/// Tag name prefix for MathML namespace elements (e.g., `math:msup`).
pub const MATH_ML_NAMESPACE = "mathml";

test "namespace constants" {
    try std.testing.expectEqualStrings("svg", SVG_NAMESPACE);
    try std.testing.expectEqualStrings("mathml", MATH_ML_NAMESPACE);
}
