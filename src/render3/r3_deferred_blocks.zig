/// R3 Deferred Blocks — Convert parsed @defer triggers to R3 AST
///
/// Port of: compiler/src/render3/render3/.ts (308 LoC)
const std = @import("std");

/// DeferredBlockTriggers — parsed @defer trigger configuration.
pub const DeferredBlockTriggers = struct {
    on_trigger: ?[]const u8 = null,
    when_trigger: ?[]const u8 = null,
    prefetch_on: ?[]const u8 = null,
    prefetch_when: ?[]const u8 = null,
    placeholder: ?[]const u8 = null,
    loading: ?[]const u8 = null,
    error: ?[]const u8 = null,
};

/// Convert parsed trigger config to R3 DeferredBlock node.
pub fn buildDeferredBlock(triggers: DeferredBlockTriggers) DeferredBlockTriggers {
    return triggers; // Pass-through — actual R3 node creation is in r3_template_transform
}
