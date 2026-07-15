/// Compiler Configuration
///
/// Minimal config struct — Zig doesn't need complex option objects.
/// comptime defaults for all fields.
const std = @import("std");

pub const Config = struct {
    /// Preserve whitespaces in templates
    preserve_whitespaces: bool = false,
    /// i18n: use external message IDs
    i18n_use_external_ids: bool = false,
    /// Enable strict null checks in expressions
    strict_null_checks: bool = true,
    /// Compilation mode: full or DOM-only
    full_template_type_check: bool = true,
    /// Enable source maps
    source_maps: bool = false,
    /// Optimize for size (minify output)
    optimize_for_size: bool = false,
    /// Use short instruction names (ɵɵelement vs ɵɵelementStart)
    short_instruction_names: bool = true,
    /// HMR (Hot Module Replacement) support
    enable_hmr: bool = false,
    /// Inline styles limit before extracting to external file
    inline_styles_limit: u32 = 10000,
    /// Debug info generation
    debug_info: bool = false,
};

pub const ViewEncapsulation = enum(u8) {
    Emulated = 0,
    None = 1,
    ShadowDom = 2,
};

pub const ChangeDetectionStrategy = enum(u8) {
    Default = 0,
    OnPush = 1,
};

// ─── Tests ────────────────────────────────────────────────────

test "Config defaults" {
    const config = Config{};
    try std.testing.expect(!config.preserve_whitespaces);
    try std.testing.expect(config.strict_null_checks);
    try std.testing.expect(config.short_instruction_names);
}
