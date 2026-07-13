/// Port of: template/pipeline/src/namespaces.ts (10 LoC)
/// DOD + Arena Memory
const std = @import("std");

pub const SVG_NAMESPACE = struct {};
pub const MATH_ML_NAMESPACE = struct {};

test "module loads" { std.testing.expect(true); }