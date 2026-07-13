/// Legacy Optional Chaining Default — Compatibility for old Angular versions
///
/// Port of: compiler/src/legacy_optional_chaining_default.ts (15 LoC) — 100% match
const std = @import("std");

/// Default value for legacy optional chaining behavior.
/// When true, the compiler uses the old (pre-Angular 14) behavior
/// for optional chaining in templates, which wraps the entire
/// expression in a null check rather than using native ?. operator.
pub const LEGACY_OPTIONAL_CHAINING: bool = false;

/// Check if legacy optional chaining should be used based on the
/// Angular version configuration.
pub fn shouldUseLegacyOptionalChaining(config_value: ?bool) bool {
    return config_value orelse LEGACY_OPTIONAL_CHAINING;
}
