/// IR Traits — Op trait markers (DOD: comptime bitset instead of runtime symbols)
///
/// Port of: compiler/src/template/pipeline/ir/src/traits.ts (167 LoC)
///
/// DOD patterns:
///   - TS uses Symbol markers for traits; Zig uses comptime bitset
///   - No runtime overhead — traits checked at compile time
///   - Packed struct for cache-friendly trait queries
const std = @import("std");

/// OpTrait — bitset of operation traits (DOD: packed struct, 1 byte).
pub const OpTrait = packed struct(u8) {
    consumes_slot: bool = false,
    depends_on_slot_context: bool = false,
    consumes_vars: bool = false,
    uses_var_offset: bool = false,
    _: u4 = 0,
};

/// TRAIT_CONSUMES_SLOT — trait constant for ops that consume a slot.
pub const TRAIT_CONSUMES_SLOT: OpTrait = .{ .consumes_slot = true };

/// TRAIT_DEPENDS_ON_SLOT_CONTEXT — trait constant for ops that depend on slot context.
pub const TRAIT_DEPENDS_ON_SLOT_CONTEXT: OpTrait = .{ .depends_on_slot_context = true };

/// TRAIT_CONSUMES_VARS — trait constant for ops that consume variables.
pub const TRAIT_CONSUMES_VARS: OpTrait = .{ .consumes_vars = true };

/// TRAIT_USES_VAR_OFFSET — trait constant for ops that use var offset.
pub const TRAIT_USES_VAR_OFFSET: OpTrait = .{ .uses_var_offset = true };

/// Check if an op has a specific trait.
pub fn hasTrait(trait_set: OpTrait, trait: OpTrait) bool {
    const mask: u8 = @bitCast(trait);
    const set: u8 = @bitCast(trait_set);
    return (set & mask) == mask;
}

/// Add a trait to a trait set.
pub fn addTrait(trait_set: *OpTrait, trait: OpTrait) void {
    const mask: u8 = @bitCast(trait);
    const set: u8 = @bitCast(trait_set.*);
    trait_set.* = @bitCast(set | mask);
}

/// Remove a trait from a trait set.
pub fn removeTrait(trait_set: *OpTrait, trait: OpTrait) void {
    const mask: u8 = @bitCast(trait);
    const set: u8 = @bitCast(trait_set.*);
    trait_set.* = @bitCast(set & ~mask);
}

/// ConsumesSlotOpTrait — marks an operation as requiring slot allocation.
/// DOD: This is just a set of fields, not a separate type.
pub const ConsumesSlotOpTrait = struct {
    handle: ?u32 = null,
    num_slots_used: u32 = 1,
    xref: u32 = 0,
};

/// DependsOnSlotContextOpTrait — marks an operation as depending on a slot context.
pub const DependsOnSlotContextOpTrait = struct {
    slot_xref: u32 = 0,
};

/// ConsumesVarsTrait — marks an operation as consuming view variables.
pub const ConsumesVarsTrait = struct {
    vars_used: u32 = 0,
};

/// UsesVarOffsetTrait — marks an operation as using a variable offset.
pub const UsesVarOffsetTrait = struct {
    var_offset: u32 = 0,
};

test "trait bitset" {
    var traits: OpTrait = .{};
    try std.testing.expect(!hasTrait(traits, TRAIT_CONSUMES_SLOT));

    addTrait(&traits, TRAIT_CONSUMES_SLOT);
    try std.testing.expect(hasTrait(traits, TRAIT_CONSUMES_SLOT));
    try std.testing.expect(!hasTrait(traits, TRAIT_CONSUMES_VARS));

    addTrait(&traits, TRAIT_CONSUMES_VARS);
    try std.testing.expect(hasTrait(traits, TRAIT_CONSUMES_SLOT));
    try std.testing.expect(hasTrait(traits, TRAIT_CONSUMES_VARS));

    removeTrait(&traits, TRAIT_CONSUMES_SLOT);
    try std.testing.expect(!hasTrait(traits, TRAIT_CONSUMES_SLOT));
    try std.testing.expect(hasTrait(traits, TRAIT_CONSUMES_VARS));
}

test "trait size" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(OpTrait));
}

pub fn hasDependsOnSlotContextTrait(allocator: std.mem.Allocator) void {
    _ = allocator;
}

pub fn hasConsumesVarsTrait(allocator: std.mem.Allocator) void {
    _ = allocator;
}
